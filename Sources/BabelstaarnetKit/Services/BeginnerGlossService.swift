import Foundation
import BabelCore
import BabelLexicon
import BabelOCR
import BabelSpeech
import BabelTranslate
import LanguageDanish

/// Explanations of common words, written in the language being learned.
///
/// The table is a local answer for a reader with no connection to a
/// translation engine; `clean` is what makes an engine's answer fit in a
/// bubble and discards the ones that say nothing.
struct BeginnerGlossService: Sendable {
    private let language: SourceLanguage

    init(language: SourceLanguage) {
        self.language = language
    }

    func localExplanation(for word: String) -> String? {
        language.beginnerGlosses[language.normalized(word)]
    }

    func clean(explanation: String) -> String {
        let compact = explanation
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else {
            return ""
        }
        let semanticText = language.normalized(compact)
        guard !language.vacuousExplanations.contains(semanticText) else {
            return ""
        }
        let words = compact.split(whereSeparator: \Character.isWhitespace)
        let limited = words.prefix(24).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;:-"))
        guard limited.last.map({ ".!?".contains($0) }) != true else {
            return limited
        }
        return limited + "."
    }
}
