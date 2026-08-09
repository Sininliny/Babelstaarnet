import Foundation

enum OCRTextQualityPolicy {
    static func plausibleRegions(
        from regions: [TextRegion]
    ) -> [TextRegion] {
        regions.filter { region in
            !region.words.isEmpty
                && region.words.allSatisfy {
                    isPlausibleWord($0.sourceText)
                }
        }
    }

    static func isPlausibleWord(_ value: String) -> Bool {
        let letters = value.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
        }
        guard !letters.isEmpty else {
            return true
        }

        let allUppercase = letters.allSatisfy {
            CharacterSet.uppercaseLetters.contains($0)
        }
        guard !allUppercase else {
            return true
        }

        // Long lowercase Danish words are often compounds, so length alone is
        // not suspicious. A lowercase q that is not followed by u is a much
        // stronger sign of a g/q OCR substitution in that setting. Keep short
        // loanwords and capitalized names eligible for recognition.
        let allLowercase = letters.allSatisfy {
            CharacterSet.lowercaseLetters.contains($0)
        }
        if allLowercase, letters.count >= 10 {
            let characters = Array(
                value.lowercased(with: Locale(identifier: "da_DK"))
                    .filter(\Character.isLetter)
            )
            for index in characters.indices where characters[index] == "q" {
                let next = characters.index(after: index)
                if next == characters.endIndex || characters[next] != "u" {
                    return false
                }
            }
        }

        var hasSeenLowercase = false
        var uppercaseAfterLowercase = 0
        for scalar in letters {
            if CharacterSet.lowercaseLetters.contains(scalar) {
                hasSeenLowercase = true
            } else if hasSeenLowercase,
                      CharacterSet.uppercaseLetters.contains(scalar) {
                uppercaseAfterLowercase += 1
            }
        }
        return uppercaseAfterLowercase < 2
    }
}
