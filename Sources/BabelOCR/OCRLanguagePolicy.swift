import BabelCore
import CoreGraphics
import Foundation
import NaturalLanguage

/// Which recognized regions are plausibly in the language being learned.
///
/// Short price and commerce phrases are often classified as another language
/// even when they are not. Classification is only relaxed for the exact OCR
/// line under the pointer; background regions remain strict.
struct OCRLanguagePolicy: Sendable {
    private let language: SourceLanguage
    private let permitRelatedLatin: Bool

    init(language: SourceLanguage, permitRelatedLatin: Bool = false) {
        self.language = language
        self.permitRelatedLatin = permitRelatedLatin
    }

    func candidates(
        from regions: [TextRegion],
        focusPoint: CGPoint?
    ) -> [TextRegion] {
        let recognizer = NLLanguageRecognizer()
        let hints = language.ocr
        let expected = language.naturalLanguage

        var candidates: [TextRegion] = []
        for region in regions {
            recognizer.reset()
            recognizer.processString(region.sourceText)
            let probabilities = recognizer.languageHypotheses(
                withMaximum: 3
            )
            let confidence = Double(
                probabilities[expected] ?? 0
            )

            if recognizer.dominantLanguage == expected
                || confidence >= hints.minimumConfidence
                || region.sourceText.rangeOfCharacter(
                    from: hints.distinctiveCharacters
                ) != nil {
                candidates.append(region)
                continue
            }

            guard let focusPoint,
                  region.words.contains(where: {
                      $0.frame
                          .insetBy(dx: -4, dy: -5)
                          .contains(focusPoint)
                  }) else {
                continue
            }

            if confidence >= hints.minimumFocusedConfidence {
                candidates.append(region)
                continue
            }
            // With generic Latin recognition, a short Danish line can be
            // classified as its close Scandinavian neighbour. Only relax the
            // focused line, and only when Vision lacks the requested dictionary.
            if permitRelatedLatin, language.code == "da",
               let detected = recognizer.dominantLanguage,
               ["no", "nb", "nn", "sv"].contains(detected.rawValue) {
                candidates.append(region); continue
            }

            let strongestLanguageConfidence = probabilities.values.reduce(
                0.0
            ) { current, probability in
                max(current, Double(probability))
            }
            if strongestLanguageConfidence
                < hints.confidentOtherLanguageThreshold {
                candidates.append(region)
            }
        }
        return candidates
    }
}
