import CoreGraphics
import Foundation
import NaturalLanguage

enum OCRLanguagePolicy {
    // Short price and commerce phrases are often classified as another
    // language even when they are Danish. Only relax classification for the
    // exact OCR line under the pointer; background regions remain strict.
    static let minimumDanishConfidence: Double = 0.2
    static let minimumFocusedDanishConfidence: Double = 0.1
    static let confidentOtherLanguageThreshold: Double = 0.65

    static func danishCandidates(
        from regions: [TextRegion],
        focusPoint: CGPoint?
    ) -> [TextRegion] {
        let recognizer = NLLanguageRecognizer()
        let distinctDanishLetters = CharacterSet(
            charactersIn: "æøåÆØÅ"
        )

        var candidates: [TextRegion] = []
        for region in regions {
            recognizer.reset()
            recognizer.processString(region.sourceText)
            let probabilities = recognizer.languageHypotheses(
                withMaximum: 3
            )
            let danishConfidence = Double(
                probabilities[.danish] ?? 0
            )

            if recognizer.dominantLanguage == .danish
                || danishConfidence >= minimumDanishConfidence
                || region.sourceText.rangeOfCharacter(
                    from: distinctDanishLetters
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

            if danishConfidence >= minimumFocusedDanishConfidence {
                candidates.append(region)
                continue
            }

            let strongestLanguageConfidence = probabilities.values.reduce(
                0.0
            ) { current, probability in
                max(current, Double(probability))
            }
            if strongestLanguageConfidence
                < confidentOtherLanguageThreshold {
                candidates.append(region)
            }
        }
        return candidates
    }
}
