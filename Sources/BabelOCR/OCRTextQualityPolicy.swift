import Foundation
import BabelCore

struct OCRTextQualityPolicy: Sendable {
    private let language: SourceLanguage

    init(language: SourceLanguage) {
        self.language = language
    }

    /// Drops corrupted words and keeps the line they came from.
    ///
    /// A colour or contrast failure usually garbles one or two words in a line
    /// rather than the whole line, and rejecting the entire region for that
    /// threw away the word under the pointer along with the noise. A line is
    /// only discarded when most of it is unreadable, which is the case the
    /// original rule was written for.
    func plausibleRegions(
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

    func isPlausibleWord(_ value: String) -> Bool {
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

        // Long lowercase words are often compounds in a compounding
        // language, so length alone is not suspicious. A lowercase q that is
        // not followed by u is a much stronger sign of a g/q OCR substitution
        // in that setting. Keep short loanwords and capitalized names
        // eligible for recognition.
        let allLowercase = letters.allSatisfy {
            CharacterSet.lowercaseLetters.contains($0)
        }
        if allLowercase,
           letters.count >= language.ocr.compoundWordMinimumLength {
            let characters = Array(
                language.lowercased(value).filter(\Character.isLetter)
            )
            for index in characters.indices where characters[index] == "q" {
                let next = characters.index(after: index)
                if next == characters.endIndex || characters[next] != "u" {
                    return false
                }
            }
        }

        // A capital at the end of an otherwise lowercase word is a misread
        // ascender, not a spelling: "nyt" came back as "nyL". One stray letter
        // is enough to change which word gets looked up, and the answer that
        // follows carries no sign of it — "nyL" reached the translator, came
        // back unchanged, was retried in lower case, and returned "kidney",
        // which was then presented as the meaning of a word that says "new".
        // A language that cannot end a word in a capital makes this a safe
        // rejection; the all-uppercase case that would is accepted above.
        if !language.ocr.endsWordInCapital,
           let last = letters.last,
           CharacterSet.uppercaseLetters.contains(last),
           letters.dropLast().contains(where: {
               CharacterSet.lowercaseLetters.contains($0)
           }) {
            return false
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
