import Foundation
import NaturalLanguage
import Vision
import BabelCore

enum OCRError: LocalizedError {
    case requestFailed

    public var errorDescription: String? {
        "The on-device OCR request failed."
    }
}

public actor OCRService {
    private struct CacheKey: Hashable {
        let displayID: CGDirectDisplayID
        let frameX: Int
        let frameY: Int
        let frameWidth: Int
        let frameHeight: Int
        let imageWidth: Int
        let imageHeight: Int
        let imageHash: Int
        let focusX: Int
        let focusY: Int
    }

    private struct CachedResult {
        let regions: [TextRegion]
        let engine: String
    }

    private struct VisionResult: Sendable {
        let regions: [TextRegion]
        let confidenceByRegionID: [UUID: Float]
    }

    private let language: SourceLanguage
    private let languagePolicy: OCRLanguagePolicy
    private let textQualityPolicy: OCRTextQualityPolicy
    private let tesseract: TesseractOCRService

    public init(language: SourceLanguage) {
        self.language = language
        self.languagePolicy = OCRLanguagePolicy(language: language)
        self.textQualityPolicy = OCRTextQualityPolicy(language: language)
        self.tesseract = TesseractOCRService(
            languageCode: language.ocr.tesseractCode
        )
    }
    private let resultCache = BoundedCache<CacheKey, CachedResult>(
        capacity: 12
    )
    /// Whether the installed Tesseract can actually read this language,
    /// remembered because answering it costs a process launch.
    private var tesseractReadsLanguage: Bool?

    public func isOpenSourceEngineReady() async -> Bool {
        let ready = await tesseract.isReady()
        tesseractReadsLanguage = ready
        return ready
    }

    /// An installed Tesseract is not a usable one. Routing on the executable
    /// alone sent every scan through four processes that opened, failed to find
    /// dan.traineddata, and exited — after the capture had been encoded as PNG
    /// for each of them — before the reading fell back to Vision anyway.
    private func tesseractCanReadLanguage() async -> Bool {
        if let tesseractReadsLanguage {
            return tesseractReadsLanguage
        }
        let ready = await tesseract.isReady()
        tesseractReadsLanguage = ready
        return ready
    }

    /// Loads the Vision text recognizer before the first hover needs it.
    ///
    /// The first accurate request in a process pays a one-time model load that
    /// was measured at tens of seconds on a cold system. Paying it during
    /// activation, alongside capture metadata and the translation workers,
    /// keeps it out of the reading path.
    public func warmUp() async {
        _ = try? await Self.warmUpVision(
            recognitionLanguages: language.ocr.recognitionLanguages
        )
    }

    public func recognizeText(
        in capture: CapturedDisplay,
        focusPoint: CGPoint? = nil
    ) async throws -> (regions: [TextRegion], engine: String) {
        let cacheKey = Self.cacheKey(
            for: capture,
            focusPoint: focusPoint
        )
        if let cacheKey,
           let cached = resultCache[cacheKey] {
            return (cached.regions, cached.engine)
        }

        // Each pass below is expensive enough to be worth remembering rather
        // than repeating. The fallback used to finish by running accurate
        // Vision on the untouched crop and then on the colour-separated one —
        // both of which the focused attempts above had already run and thrown
        // away. Hovering a blank area fails every focused gate, so on a Mac
        // without Tesseract that made the most common pointer position pay for
        // the same two passes twice.
        var rawRegions: [TextRegion]?
        var contrastRegions: [TextRegion]?

        // Only the accurate recognizer is trusted with the word a learner
        // reads. Measured against rendered Danish crops, the fast level
        // recovered nothing at all below roughly 13 px text, below a 60-step
        // luminance difference, or on saturated text over a saturated
        // background — and where it did return text it silently dropped
        // æ, ø, and å while still reporting the same confidence. A stripped
        // diacritic is not a smaller error here: it changes which Danish word
        // gets translated. Accurate costs about 50 ms more per scan.
        let prefersSmallTextRecovery = focusPoint != nil
        if focusPoint != nil,
           let vision = try? await Self.recognizeWithVision(
               image: capture.image,
               in: capture,
               recognitionLevel: .accurate,
               language: language
           ) {
            try Task.checkCancellation()
            let regions = Self.candidateRegions(
                from: vision,
                focusPoint: focusPoint,
                languagePolicy: languagePolicy,
                textQualityPolicy: textQualityPolicy
            )
            rawRegions = regions
            if OCRRoutingPolicy.canUseAccurateFocusedVision(
                regions: regions,
                confidenceByRegionID: vision.confidenceByRegionID,
                focusPoint: focusPoint
            ) {
                if let refined = try await enlargedRefinement(
                    of: regions,
                    in: capture,
                    focusPoint: focusPoint
                ) {
                    return store(
                        CachedResult(
                            regions: refined,
                            engine: "Apple Vision small-text OCR"
                        ),
                        at: cacheKey
                    )
                }
                return store(
                    CachedResult(
                        regions: regions,
                        engine: "Apple Vision OCR"
                    ),
                    at: cacheKey
                )
            }
        }

        // The remaining focused failures are colour failures: a label a few
        // luminance steps from its panel, or glyphs separated from the
        // background by hue alone. Rewriting the crop to dark-on-light before
        // a second Vision pass recovers those for far less than the cost of
        // starting an external engine.
        if focusPoint != nil,
           let prepared = Self.preparedImage(from: capture.image),
           let vision = try? await Self.recognizeWithVision(
               image: prepared,
               in: capture,
               recognitionLevel: .accurate,
               language: language
           ) {
            try Task.checkCancellation()
            let regions = Self.candidateRegions(
                from: vision,
                focusPoint: focusPoint,
                languagePolicy: languagePolicy,
                textQualityPolicy: textQualityPolicy
            )
            contrastRegions = regions
            if OCRRoutingPolicy.canUseAccurateFocusedVision(
                regions: regions,
                confidenceByRegionID: vision.confidenceByRegionID,
                focusPoint: focusPoint
            ) {
                return store(
                    CachedResult(
                        regions: regions,
                        engine: "Apple Vision contrast OCR"
                    ),
                    at: cacheKey
                )
            }
        }

        try Task.checkCancellation()
        if tesseract.isAvailable,
           await tesseractCanReadLanguage(),
           let tesseractRegions = try? await tesseract.recognize(
               in: capture,
               prefersSmallText: prefersSmallTextRecovery
           ),
           !tesseractRegions.isEmpty {
            try Task.checkCancellation()
            let plausible = textQualityPolicy.plausibleRegions(
                from: tesseractRegions
            )
            let regions = languagePolicy.candidates(
                from: plausible,
                focusPoint: focusPoint
            )
            guard Self.hasUsableResult(
                regions,
                focusPoint: focusPoint
            ) else {
                return try await accurateVisionResult(
                    in: capture,
                    focusPoint: focusPoint,
                    cacheKey: cacheKey,
                    rawRegions: rawRegions,
                    contrastRegions: contrastRegions
                )
            }
            return store(
                CachedResult(regions: regions, engine: "Tesseract OCR"),
                at: cacheKey
            )
        }

        return try await accurateVisionResult(
            in: capture,
            focusPoint: focusPoint,
            cacheKey: cacheKey,
            rawRegions: rawRegions,
            contrastRegions: contrastRegions
        )
    }

    /// The whole-crop reading, used when nothing focused could be trusted.
    ///
    /// `rawRegions` and `contrastRegions` carry whichever of these two passes
    /// the focused attempts already ran, so reaching the fallback costs only
    /// the passes that have not been paid for yet.
    private func accurateVisionResult(
        in capture: CapturedDisplay,
        focusPoint: CGPoint?,
        cacheKey: CacheKey?,
        rawRegions: [TextRegion]? = nil,
        contrastRegions: [TextRegion]? = nil
    ) async throws -> (regions: [TextRegion], engine: String) {
        try Task.checkCancellation()
        let regions: [TextRegion]
        if let rawRegions {
            regions = rawRegions
        } else {
            let vision = try await Self.recognizeWithVision(
                image: capture.image,
                in: capture,
                recognitionLevel: .accurate,
                language: language
            )
            regions = Self.candidateRegions(
                from: vision,
                focusPoint: focusPoint,
                languagePolicy: languagePolicy,
                textQualityPolicy: textQualityPolicy
            )
        }

        guard regions.isEmpty else {
            return store(
                CachedResult(
                    regions: regions,
                    engine: "Apple Vision fallback"
                ),
                at: cacheKey
            )
        }

        let recovered: [TextRegion]
        if let contrastRegions {
            recovered = contrastRegions
        } else if let prepared = Self.preparedImage(from: capture.image),
                  let contrastVision = try? await Self.recognizeWithVision(
                      image: prepared,
                      in: capture,
                      recognitionLevel: .accurate,
                      language: language
                  ) {
            try Task.checkCancellation()
            recovered = Self.candidateRegions(
                from: contrastVision,
                focusPoint: focusPoint,
                languagePolicy: languagePolicy,
                textQualityPolicy: textQualityPolicy
            )
        } else {
            return store(
                CachedResult(
                    regions: regions,
                    engine: "Apple Vision fallback"
                ),
                at: cacheKey
            )
        }

        return store(
            CachedResult(
                regions: recovered,
                engine: recovered.isEmpty
                    ? "Apple Vision fallback"
                    : "Apple Vision contrast OCR"
            ),
            at: cacheKey
        )
    }

    /// Re-reads dense small text from an enlarged crop of the pointer's line,
    /// returning the reading only when it recovers more of that line.
    ///
    /// At capture scale a form or table line comes back with its diacritics
    /// dropped — "Mnedlig" for "Månedlig" — which is a different word to
    /// translate. Enlarging restores the strokes those marks are made of. The
    /// pass is skipped entirely unless the recognized text really is small.
    ///
    /// Two things follow from cropping to the line before enlarging rather than
    /// redrawing the whole capture. Cost stops scaling with the capture: a
    /// cursor-sized crop at 2x is four times the pixels Vision has to read,
    /// while one line is a small fraction of one, which leaves room to enlarge
    /// further exactly where the text is smallest. And because only one line is
    /// re-read, it is substituted into the reading the base pass produced
    /// instead of replacing it, so the rest of the sentence survives a crop
    /// that no longer contains it.
    private func enlargedRefinement(
        of regions: [TextRegion],
        in capture: CapturedDisplay,
        focusPoint: CGPoint?
    ) async throws -> [TextRegion]? {
        guard let focusPoint,
              let index = Self.focusedRegionIndex(
                  in: regions,
                  at: focusPoint
              ),
              let advance = Self.glyphAdvance(in: regions[index]),
              advance <= Self.smallTextAdvance,
              let window = Self.window(
                  around: regions[index].frame,
                  in: capture
              ),
              let cropped = capture.image.cropping(to: window.pixelRect),
              let enlarged = OCRImagePreparation.enlarged(
                  cropped,
                  scale: Self.refinementScale(forAdvance: advance)
              ),
              let vision = try? await Self.recognizeWithVision(
                  image: enlarged,
                  displayFrame: window.globalFrame,
                  screenFrame: capture.screenFrame,
                  displayID: capture.displayID,
                  recognitionLevel: .accurate,
                  language: language
              ) else {
            return nil
        }
        try Task.checkCancellation()
        let refined = Self.candidateRegions(
            from: vision,
            focusPoint: focusPoint,
            languagePolicy: languagePolicy,
            textQualityPolicy: textQualityPolicy
        )
        guard OCRRoutingPolicy.canUseAccurateFocusedVision(
            regions: refined,
            confidenceByRegionID: vision.confidenceByRegionID,
            focusPoint: focusPoint
        ), let refinedIndex = Self.focusedRegionIndex(
            in: refined,
            at: focusPoint
        ), Self.letterCount(in: refined[refinedIndex])
            > Self.letterCount(in: regions[index]) else {
            return nil
        }
        var merged = regions
        merged[index] = refined[refinedIndex]
        return merged
    }

    /// How much the line is enlarged before it is read again.
    ///
    /// Vision keeps Danish diacritics attached once a glyph advance is around
    /// eleven points; below that the mark falls within a pixel or two of the
    /// stroke it belongs to and gets absorbed into it. Enlarging one line is
    /// cheap enough to aim for that rather than settling for a fixed doubling,
    /// so the smallest text — the text that lost the most — is enlarged most.
    private static func refinementScale(
        forAdvance advance: CGFloat
    ) -> CGFloat {
        let target: CGFloat = 11
        return min(max((target / max(advance, 0.5)).rounded(), 2), 4)
    }

    /// Average glyph width, in points, below which the pointer's line counts as
    /// fine print.
    ///
    /// Width per character is used rather than box height because Vision
    /// reports a line box whose height follows whichever ascenders and
    /// descenders happen to appear in the line, not the type size: measured on
    /// these fixtures, 8.5 point table text reported a 14.6 point box while
    /// 17 point body text reported 15.5. Advance separates the same two cases
    /// as 4.3 against 8.4, with every measured scenario falling either below
    /// 4.4 or above 6.8.
    private static let smallTextAdvance: CGFloat = 5.5

    /// The line the pointer is resting on. Only that line matters: a page
    /// mixing a headline with a fine-print table would otherwise pay for the
    /// extra pass on every hover, including hovers over text that was already
    /// read correctly.
    public static func focusedRegionIndex(
        in regions: [TextRegion],
        at focusPoint: CGPoint
    ) -> Int? {
        regions.firstIndex { region in
            region.words.contains {
                $0.frame.insetBy(dx: -4, dy: -5).contains(focusPoint)
            }
        }
    }

    /// Average glyph width in points, which is how a line's type size is
    /// measured here. Returns `nil` when the line carries no measurable text.
    public static func glyphAdvance(in region: TextRegion) -> CGFloat? {
        let width = region.words.reduce(0) { $0 + $1.frame.width }
        let characters = region.words.reduce(0) { $0 + $1.sourceText.count }
        guard characters > 0, width > 0 else {
            return nil
        }
        return width / CGFloat(characters)
    }

    /// Letters recovered in a line. A restored diacritic lengthens the word, so
    /// this separates "Månedlig" from "Mnedlig" where word counts and
    /// confidences are identical.
    public static func letterCount(in region: TextRegion) -> Int {
        region.sourceText.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
        }.count
    }

    /// A crop of the capture, in image pixels, paired with the screen rectangle
    /// it covers.
    ///
    /// Recognition on a crop reports boxes normalized to that crop, so the
    /// screen rectangle has to describe the crop exactly. Both are therefore
    /// derived from the same pixel-snapped rectangle rather than from the
    /// requested one, which cannot in general land on a pixel boundary.
    struct ImageWindow: Equatable {
        let pixelRect: CGRect
        let globalFrame: CGRect
    }

    /// Extra context kept around a line, as a multiple of its own height.
    /// Vision segments a line by what surrounds it, and a crop crowding the
    /// glyphs against its edge reads worse than the capture it came from.
    private static let windowPaddingInLineHeights: CGFloat = 1

    /// Builds the crop covering `frame` plus context, or `nil` when the capture
    /// geometry cannot be resolved.
    static func window(
        around frame: CGRect,
        in capture: CapturedDisplay
    ) -> ImageWindow? {
        let captureFrame = capture.frame
        guard captureFrame.width > 0,
              captureFrame.height > 0,
              capture.image.width > 0,
              capture.image.height > 0 else {
            return nil
        }
        let pixelsPerPointX = CGFloat(capture.image.width) / captureFrame.width
        let pixelsPerPointY = CGFloat(capture.image.height)
            / captureFrame.height
        let padding = max(
            frame.height * windowPaddingInLineHeights,
            8
        )
        let padded = frame.insetBy(dx: -padding, dy: -padding)
            .intersection(captureFrame)
        guard !padded.isNull, padded.width > 0, padded.height > 0 else {
            return nil
        }

        // Image rows run downwards from the top of the capture while screen
        // coordinates run upwards from its bottom, so the vertical origin is
        // measured from `maxY` rather than `minY`.
        let left = ((padded.minX - captureFrame.minX) * pixelsPerPointX)
            .rounded(.down)
        let top = ((captureFrame.maxY - padded.maxY) * pixelsPerPointY)
            .rounded(.down)
        let right = ((padded.maxX - captureFrame.minX) * pixelsPerPointX)
            .rounded(.up)
        let bottom = ((captureFrame.maxY - padded.minY) * pixelsPerPointY)
            .rounded(.up)
        let pixelRect = CGRect(
            x: max(left, 0),
            y: max(top, 0),
            width: min(right, CGFloat(capture.image.width)) - max(left, 0),
            height: min(bottom, CGFloat(capture.image.height)) - max(top, 0)
        )
        guard pixelRect.width >= 1, pixelRect.height >= 1 else {
            return nil
        }

        return ImageWindow(
            pixelRect: pixelRect,
            globalFrame: CGRect(
                x: captureFrame.minX + pixelRect.minX / pixelsPerPointX,
                y: captureFrame.maxY - pixelRect.maxY / pixelsPerPointY,
                width: pixelRect.width / pixelsPerPointX,
                height: pixelRect.height / pixelsPerPointY
            )
        )
    }

    private func store(
        _ result: CachedResult,
        at cacheKey: CacheKey?
    ) -> (regions: [TextRegion], engine: String) {
        if let cacheKey {
            resultCache[cacheKey] = result
        }
        return (result.regions, result.engine)
    }

    private nonisolated static func candidateRegions(
        from vision: VisionResult,
        focusPoint: CGPoint?,
        languagePolicy: OCRLanguagePolicy,
        textQualityPolicy: OCRTextQualityPolicy
    ) -> [TextRegion] {
        languagePolicy.candidates(
            from: textQualityPolicy.plausibleRegions(from: vision.regions),
            focusPoint: focusPoint
        )
    }

    /// Rewrites the crop as dark text on a light background so a second Vision
    /// pass sees separation the original colours did not provide.
    private nonisolated static func preparedImage(
        from image: CGImage
    ) -> CGImage? {
        guard let grayscale = OCRImagePreparation.separated(from: image) else {
            return nil
        }
        return OCRImagePreparation.image(from: grayscale)
    }

    private nonisolated static func hasUsableResult(
        _ regions: [TextRegion],
        focusPoint: CGPoint?
    ) -> Bool {
        guard !regions.isEmpty else {
            return false
        }
        guard let focusPoint else {
            return true
        }
        return regions.contains { region in
            region.words.contains { word in
                word.frame
                    .insetBy(dx: -4, dy: -5)
                    .contains(focusPoint)
            }
        }
    }

    /// Runs one accurate recognition on a throwaway crop so the model load is
    /// paid before a learner is waiting on it.
    private nonisolated static func warmUpVision(
        recognitionLanguages: [String]
    ) async throws {
        let worker = Task.detached(priority: .utility) {
            let width = 64
            let height = 32
            var pixels = [UInt8](repeating: 255, count: width * height)
            for row in 8..<24 {
                for column in 8..<56 where column % 6 < 2 {
                    pixels[row * width + column] = 0
                }
            }
            guard let image = OCRImagePreparation.image(
                from: OCRImagePreparation.Grayscale(
                    pixels: pixels,
                    width: width,
                    height: height
                )
            ) else {
                return
            }
            let request = Self.textRequest(
                recognitionLevel: .accurate,
                imageHeight: height,
                recognitionLanguages: recognitionLanguages
            )
            try? VNImageRequestHandler(
                cgImage: image,
                orientation: .up
            ).perform([request])
        }
        await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// The smallest text worth looking for, in image pixels.
    ///
    /// `minimumTextHeight` is a fraction of the image, so a fixed fraction
    /// means a different real size on every crop: the adaptive planner produces
    /// captures from roughly 250 to 820 points tall, and 0.002 of the tallest
    /// of them asks Vision to search scales where a line is three pixels high.
    /// Nothing legible lives there — the recognizer recovered nothing under
    /// about 13 px even before diacritics came into it — so the floor is stated
    /// in pixels and converted per image instead.
    private static let minimumTextPixels: CGFloat = 8

    /// The fast level's floor is its own measured one: it recovered nothing at
    /// all below roughly 13 px, so asking it for less is asking for noise.
    private static let minimumFastTextPixels: CGFloat = 13

    private nonisolated static func textRequest(
        recognitionLevel: VNRequestTextRecognitionLevel,
        imageHeight: Int,
        recognitionLanguages: [String]
    ) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.recognitionLanguages = recognitionLanguages
        // Language correction is what keeps æ, ø, and å attached to the word.
        // It belongs to the accurate level only; on the fast level the same
        // flag measurably replaced those letters with a, o, and noise.
        request.usesLanguageCorrection = recognitionLevel == .accurate
        request.minimumTextHeight = Float(
            minimumTextHeight(
                recognitionLevel: recognitionLevel,
                imageHeight: imageHeight
            )
        )
        return request
    }

    public static func minimumTextHeight(
        recognitionLevel: VNRequestTextRecognitionLevel,
        imageHeight: Int
    ) -> CGFloat {
        let floor: CGFloat = recognitionLevel == .accurate
            ? minimumTextPixels
            : minimumFastTextPixels
        guard imageHeight > 0 else {
            return recognitionLevel == .accurate ? 0.002 : 0.004
        }
        // Clamped so a very small crop — one enlarged line, say — cannot ask
        // for text taller than the crop itself.
        return min(max(floor / CGFloat(imageHeight), 0.002), 0.08)
    }

    private nonisolated static func recognizeWithVision(
        image: CGImage,
        in capture: CapturedDisplay,
        recognitionLevel: VNRequestTextRecognitionLevel,
        language: SourceLanguage
    ) async throws -> VisionResult {
        try await recognizeWithVision(
            image: image,
            displayFrame: capture.frame,
            screenFrame: capture.screenFrame,
            displayID: capture.displayID,
            recognitionLevel: recognitionLevel,
            language: language
        )
    }

    /// Recognizes `image` and maps every box it reports into screen
    /// coordinates.
    ///
    /// `displayFrame` is the screen rectangle `image` covers, which is the
    /// capture's own frame for a whole-capture pass and the window's frame when
    /// only part of the capture was re-read.
    private nonisolated static func recognizeWithVision(
        image: CGImage,
        displayFrame: CGRect,
        screenFrame: CGRect,
        displayID: CGDirectDisplayID,
        recognitionLevel: VNRequestTextRecognitionLevel,
        language: SourceLanguage
    ) async throws -> VisionResult {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let request = Self.textRequest(
                recognitionLevel: recognitionLevel,
                imageHeight: image.height,
                recognitionLanguages: language.ocr.recognitionLanguages
            )

            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            try handler.perform([request])
            try Task.checkCancellation()

            guard let observations = request.results else {
                throw OCRError.requestFailed
            }

            var confidenceByRegionID: [UUID: Float] = [:]
            let regions: [TextRegion] = observations.compactMap {
                observation -> TextRegion? in
                guard let candidate = observation.topCandidates(1).first else {
                    return nil
                }
                let source = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard source.count > 1 else {
                    return nil
                }

                let lineFrame = Self.globalRect(
                    observation.boundingBox,
                    displayFrame: displayFrame
                )
                let words = Self.words(
                    in: candidate,
                    displayFrame: displayFrame,
                    screenFrame: screenFrame,
                    displayID: displayID,
                    naturalLanguage: language.naturalLanguage
                )
                let region = TextRegion(
                    sourceText: source,
                    frame: lineFrame,
                    screenFrame: screenFrame,
                    displayID: displayID,
                    words: words
                )
                confidenceByRegionID[region.id] = candidate.confidence
                return region
            }
            return VisionResult(
                regions: regions,
                confidenceByRegionID: confidenceByRegionID
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private nonisolated static func cacheKey(
        for capture: CapturedDisplay,
        focusPoint: CGPoint?
    ) -> CacheKey? {
        guard let data = capture.image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        var hasher = Hasher()
        hasher.combine(bytes: UnsafeRawBufferPointer(
            start: bytes,
            count: CFDataGetLength(data)
        ))
        let focusScale: CGFloat = 8
        return CacheKey(
            displayID: capture.displayID,
            frameX: Int((capture.frame.minX * 2).rounded()),
            frameY: Int((capture.frame.minY * 2).rounded()),
            frameWidth: Int((capture.frame.width * 2).rounded()),
            frameHeight: Int((capture.frame.height * 2).rounded()),
            imageWidth: capture.image.width,
            imageHeight: capture.image.height,
            imageHash: hasher.finalize(),
            focusX: focusPoint.map {
                Int(($0.x / focusScale).rounded())
            } ?? .min,
            focusY: focusPoint.map {
                Int(($0.y / focusScale).rounded())
            } ?? .min
        )
    }

    public static func globalRect(_ normalizedRect: CGRect, displayFrame: CGRect) -> CGRect {
        CGRect(
            x: displayFrame.minX + (normalizedRect.minX * displayFrame.width),
            y: displayFrame.minY + (normalizedRect.minY * displayFrame.height),
            width: normalizedRect.width * displayFrame.width,
            height: normalizedRect.height * displayFrame.height
        )
    }

    private static func words(
        in recognizedText: VNRecognizedText,
        displayFrame: CGRect,
        screenFrame: CGRect,
        displayID: CGDirectDisplayID,
        naturalLanguage: NLLanguage
    ) -> [WordRegion] {
        let source = recognizedText.string
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = source
        tokenizer.setLanguage(naturalLanguage)

        var regions: [WordRegion] = []
        tokenizer.enumerateTokens(
            in: source.startIndex..<source.endIndex
        ) { range, _ in
            let word = String(source[range])
                .trimmingCharacters(in: .punctuationCharacters)
            guard !word.isEmpty,
                  let box = try? recognizedText.boundingBox(for: range) else {
                return true
            }

            regions.append(
                WordRegion(
                    sourceText: word,
                    frame: globalRect(box.boundingBox, displayFrame: displayFrame),
                    screenFrame: screenFrame,
                    displayID: displayID
                )
            )
            return true
        }
        return regions
    }

}
