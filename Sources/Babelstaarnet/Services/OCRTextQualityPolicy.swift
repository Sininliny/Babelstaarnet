import Foundation

enum OCRTextQualityPolicy {
    /// Drops corrupted words and keeps the line they came from.
    ///
    /// A colour or contrast failure usually garbles one or two words in a line
    /// rather than the whole line, and rejecting the entire region for that
    /// threw away the word under the pointer along with the noise. A line is
    /// only discarded when most of it is unreadable, which is the case the
    /// original rule was written for.
    static func plausibleRegions(
        from regions: [TextRegion]
    ) -> [TextRegion] {
        regions.compactMap { region in
            let plausible = region.words.filter {
                isPlausibleWord($0.sourceText)
            }
            guard !plausible.isEmpty,
                  plausible.count * 2 > region.words.count else {
                return nil
            }
            guard plausible.count < region.words.count else {
                return region
            }
            let frame = plausible
                .dropFirst()
                .reduce(plausible[0].frame) { $0.union($1.frame) }
            return TextRegion(
                id: region.id,
                sourceText: plausible
                    .map(\.sourceText)
                    .joined(separator: " "),
                frame: frame,
                screenFrame: region.screenFrame,
                displayID: region.displayID,
                words: plausible
            )
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
