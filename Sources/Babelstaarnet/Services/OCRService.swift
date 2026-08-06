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

        if focusPoint != nil,
           let vision = try? await Self.recognizeWithVision(
               in: capture,
               recognitionLevel: .fast
           ) {
            try Task.checkCancellation()
            let plausible = OCRTextQualityPolicy.plausibleRegions(
                from: vision.regions
            )
            let regions = OCRLanguagePolicy.danishCandidates(
                from: plausible,
                focusPoint: focusPoint
            )
            if OCRRoutingPolicy.canUseFastVision(
                regions: regions,
                confidenceByRegionID: vision.confidenceByRegionID,
                focusPoint: focusPoint
            ) {
                let result = CachedResult(
                    regions: regions,
                    engine: "Apple Vision fast OCR"
                )
                if let cacheKey {
                    resultCache[cacheKey] = result
                }
                return (result.regions, result.engine)
            }
        }

        try Task.checkCancellation()
        if tesseract.isAvailable,
           let rawRegions = try? await tesseract.recognize(in: capture),
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
            let result = CachedResult(
                regions: regions,
                engine: "Tesseract OCR"
            )
            if let cacheKey {
                resultCache[cacheKey] = result
            }
            return (result.regions, result.engine)
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
            in: capture,
            recognitionLevel: .accurate
        )
        let plausible = OCRTextQualityPolicy.plausibleRegions(
            from: vision.regions
        )
        let result = CachedResult(
            regions: OCRLanguagePolicy.danishCandidates(
                from: plausible,
                focusPoint: focusPoint
            ),
            engine: "Apple Vision fallback"
        )
        if let cacheKey {
            resultCache[cacheKey] = result
        }
        return (result.regions, result.engine)
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

    private nonisolated static func recognizeWithVision(
        in capture: CapturedDisplay,
        recognitionLevel: VNRequestTextRecognitionLevel
    ) async throws -> VisionResult {
        let image = capture.image
        let captureFrame = capture.frame
        let screenFrame = capture.screenFrame

        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = recognitionLevel
            request.recognitionLanguages = ["da-DK", "da"]
            request.usesLanguageCorrection = recognitionLevel == .accurate
            request.minimumTextHeight = 0.004

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
