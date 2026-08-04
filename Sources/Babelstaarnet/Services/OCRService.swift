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
    private let tesseract = TesseractOCRService()

    func isOpenSourceEngineReady() async -> Bool {
        await tesseract.isDanishReady()
    }

    func recognizeDanishText(
        in capture: CapturedDisplay
    ) async throws -> (regions: [TextRegion], engine: String) {
        if tesseract.isAvailable,
           let regions = try? await tesseract.recognize(in: capture),
           !regions.isEmpty {
            return (Self.danishRegions(from: regions), "Tesseract OCR")
        }

        return (
            Self.danishRegions(from: try await recognizeWithVision(in: capture)),
            "Apple Vision fallback"
        )
    }

    private func recognizeWithVision(
        in capture: CapturedDisplay
    ) async throws -> [TextRegion] {
        let image = capture.image
        let captureFrame = capture.frame
        let screenFrame = capture.screenFrame

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["da-DK", "da"]
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.004

            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            try handler.perform([request])

            guard let observations = request.results else {
                throw OCRError.requestFailed
            }

            return observations.compactMap { observation in
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
                return TextRegion(
                    sourceText: source,
                    frame: lineFrame,
                    screenFrame: screenFrame,
                    displayID: capture.displayID,
                    words: words
                )
            }
        }.value
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

    private static func danishRegions(from regions: [TextRegion]) -> [TextRegion] {
        let recognizer = NLLanguageRecognizer()
        let distinctDanishLetters = CharacterSet(
            charactersIn: "æøåÆØÅ"
        )
        return regions.filter { region in
            recognizer.reset()
            recognizer.processString(region.sourceText)
            let probabilities = recognizer.languageHypotheses(withMaximum: 3)
            return recognizer.dominantLanguage == .danish
                || (probabilities[.danish] ?? 0) >= 0.2
                || region.sourceText.rangeOfCharacter(
                    from: distinctDanishLetters
                ) != nil
        }
    }
}
