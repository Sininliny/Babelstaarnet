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
