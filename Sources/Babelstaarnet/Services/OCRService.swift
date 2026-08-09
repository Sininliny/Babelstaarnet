import Foundation
import NaturalLanguage
import Vision

enum OCRError: LocalizedError {
    case requestFailed

    var errorDescription: String? {
        "The on-device OCR request failed."
    }
}

actor OCRService {
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

    private let tesseract = TesseractOCRService()
    private let resultCache = BoundedCache<CacheKey, CachedResult>(
        capacity: 12
    )

    func isOpenSourceEngineReady() async -> Bool {
        await tesseract.isDanishReady()
    }

    /// Loads the Vision text recognizer before the first hover needs it.
    ///
    /// The first accurate request in a process pays a one-time model load that
    /// was measured at tens of seconds on a cold system. Paying it during
    /// activation, alongside capture metadata and the translation workers,
    /// keeps it out of the reading path.
    func warmUp() async {
        _ = try? await Self.warmUpVision()
    }

    func recognizeDanishText(
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
               recognitionLevel: .accurate
           ) {
            try Task.checkCancellation()
            let regions = Self.danishRegions(
                from: vision,
                focusPoint: focusPoint
            )
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
               recognitionLevel: .accurate
           ) {
            try Task.checkCancellation()
            let regions = Self.danishRegions(
                from: vision,
                focusPoint: focusPoint
            )
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
           let rawRegions = try? await tesseract.recognize(
               in: capture,
               prefersSmallText: prefersSmallTextRecovery
           ),
           !rawRegions.isEmpty {
            try Task.checkCancellation()
            let plausible = OCRTextQualityPolicy.plausibleRegions(
                from: rawRegions
            )
            let regions = OCRLanguagePolicy.danishCandidates(
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
                    cacheKey: cacheKey
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
            cacheKey: cacheKey
        )
    }

    private func accurateVisionResult(
        in capture: CapturedDisplay,
        focusPoint: CGPoint?,
        cacheKey: CacheKey?
    ) async throws -> (regions: [TextRegion], engine: String) {
        try Task.checkCancellation()
        let vision = try await Self.recognizeWithVision(
            image: capture.image,
            in: capture,
            recognitionLevel: .accurate
        )
        let regions = Self.danishRegions(
            from: vision,
            focusPoint: focusPoint
        )
        guard regions.isEmpty,
              let prepared = Self.preparedImage(from: capture.image),
              let contrastVision = try? await Self.recognizeWithVision(
                  image: prepared,
                  in: capture,
                  recognitionLevel: .accurate
              ) else {
            return store(
                CachedResult(
                    regions: regions,
                    engine: "Apple Vision fallback"
                ),
                at: cacheKey
            )
        }
        try Task.checkCancellation()
        let contrastRegions = Self.danishRegions(
            from: contrastVision,
            focusPoint: focusPoint
        )
        return store(
            CachedResult(
                regions: contrastRegions,
                engine: contrastRegions.isEmpty
                    ? "Apple Vision fallback"
                    : "Apple Vision contrast OCR"
            ),
            at: cacheKey
        )
    }

    /// Re-reads dense small text from an enlarged crop, returning the result
    /// only when it recovers more of the line under the pointer.
    ///
    /// At capture scale a form or table line comes back with its diacritics
    /// dropped — "Mnedlig" for "Månedlig" — which is a different word to
    /// translate. Enlarging restores the strokes those marks are made of. The
    /// pass is skipped entirely unless the recognized text really is small.
    private func enlargedRefinement(
        of regions: [TextRegion],
        in capture: CapturedDisplay,
        focusPoint: CGPoint?
    ) async throws -> [TextRegion]? {
        guard let focusPoint,
              Self.isSmallText(regions, at: focusPoint),
              let enlarged = OCRImagePreparation.enlarged(
                  capture.image,
                  scale: 2
              ),
              let vision = try? await Self.recognizeWithVision(
                  image: enlarged,
                  in: capture,
                  recognitionLevel: .accurate
              ) else {
            return nil
        }
        try Task.checkCancellation()
        let refined = Self.danishRegions(
            from: vision,
            focusPoint: focusPoint
        )
        guard OCRRoutingPolicy.canUseAccurateFocusedVision(
            regions: refined,
            confidenceByRegionID: vision.confidenceByRegionID,
            focusPoint: focusPoint
        ), Self.letterCount(in: refined, at: focusPoint)
            > Self.letterCount(in: regions, at: focusPoint) else {
            return nil
        }
        return refined
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

    /// Whether the line under the pointer is small enough to be worth
    /// re-reading enlarged.
    ///
    /// Only that line matters. A page mixing a headline with a fine-print
    /// table would otherwise pay for the extra pass on every hover, including
    /// hovers over text that was already read correctly.
    private nonisolated static func isSmallText(
        _ regions: [TextRegion],
        at focusPoint: CGPoint
    ) -> Bool {
        guard let region = regions.first(where: { region in
            region.words.contains {
                $0.frame.insetBy(dx: -4, dy: -5).contains(focusPoint)
            }
        }) else {
            return false
        }
        let width = region.words.reduce(0) { $0 + $1.frame.width }
        let characters = region.words.reduce(0) { $0 + $1.sourceText.count }
        guard characters > 0, width > 0 else {
            return false
        }
        return width / CGFloat(characters) <= smallTextAdvance
    }

    /// Letters recovered in the line under the pointer. A restored diacritic
    /// lengthens the word, so this separates "Månedlig" from "Mnedlig" where
    /// word counts and confidences are identical.
    private nonisolated static func letterCount(
        in regions: [TextRegion],
        at focusPoint: CGPoint
    ) -> Int {
        guard let region = regions.first(where: { region in
            region.words.contains {
                $0.frame.insetBy(dx: -4, dy: -5).contains(focusPoint)
            }
        }) else {
            return 0
        }
        return region.sourceText.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
        }.count
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

    private nonisolated static func danishRegions(
        from vision: VisionResult,
        focusPoint: CGPoint?
    ) -> [TextRegion] {
        OCRLanguagePolicy.danishCandidates(
            from: OCRTextQualityPolicy.plausibleRegions(from: vision.regions),
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
    private nonisolated static func warmUpVision() async throws {
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
            let request = Self.textRequest(recognitionLevel: .accurate)
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

    private nonisolated static func textRequest(
        recognitionLevel: VNRequestTextRecognitionLevel
    ) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.recognitionLanguages = ["da-DK", "da"]
        // Language correction is what keeps æ, ø, and å attached to the word.
        // It belongs to the accurate level only; on the fast level the same
        // flag measurably replaced those letters with a, o, and noise.
        request.usesLanguageCorrection = recognitionLevel == .accurate
        request.minimumTextHeight = recognitionLevel == .accurate
            ? 0.002
            : 0.004
        return request
    }

    private nonisolated static func recognizeWithVision(
        image: CGImage,
        in capture: CapturedDisplay,
        recognitionLevel: VNRequestTextRecognitionLevel
    ) async throws -> VisionResult {
        let captureFrame = capture.frame
        let screenFrame = capture.screenFrame

        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let request = Self.textRequest(
                recognitionLevel: recognitionLevel
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
                    displayFrame: captureFrame
                )
                let words = Self.words(
                    in: candidate,
                    displayFrame: captureFrame,
                    screenFrame: screenFrame,
                    displayID: capture.displayID
                )
                let region = TextRegion(
                    sourceText: source,
                    frame: lineFrame,
                    screenFrame: screenFrame,
                    displayID: capture.displayID,
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

    static func globalRect(_ normalizedRect: CGRect, displayFrame: CGRect) -> CGRect {
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
        displayID: CGDirectDisplayID
    ) -> [WordRegion] {
        let source = recognizedText.string
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = source
        tokenizer.setLanguage(.danish)

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
