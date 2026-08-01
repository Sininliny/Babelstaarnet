import Foundation

struct MixedLanguageExplanationService {
    private static let wordExpression = try! NSRegularExpression(
        pattern: #"[\p{L}]+(?:['’-][\p{L}]+)*"#
    )

    /// Small Danish grammar words remain as the sentence's scaffold even when
    /// the learner has not explicitly marked them as known.
    private static let grammarScaffold: Set<String> = [
        "ad", "af", "at", "da", "de", "den", "der", "det", "du",
        "eller", "en", "end", "er", "et", "for", "fordi", "fra", "han",
        "har", "hun", "hvad", "hvem", "hvor", "hvis", "i", "ikke", "jeg",
        "kan", "med", "men", "mod", "når", "og", "om", "på", "sig",
        "sin", "sit", "skal", "som", "til", "var", "ved", "vi", "vil"
    ]

    func wordsNeedingEnglish(
        in danishExplanation: String,
        replacementLimit: Int = 6,
        isFamiliar: (String) -> Bool
    ) -> [String] {
        var seen = Set<String>()
        let candidates = wordMatches(in: danishExplanation).compactMap {
            match -> String? in
            let word = normalized(match.word)
            guard word.count > 1,
                  !Self.grammarScaffold.contains(word),
                  !isFamiliar(word),
                  seen.insert(word).inserted else {
                return nil
            }
            return word
        }
        return Array(candidates.prefix(replacementLimit))
    }

    func mix(
        danishExplanation: String,
        englishByDanishWord: [String: String],
        isFamiliar: (String) -> Bool,
        wordLimit: Int = 20,
        replacementLimit: Int = 6
    ) -> String {
        let compact = danishExplanation
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else {
            return ""
        }

        let limited = completeWords(in: compact, limit: wordLimit)
        let replaceable = Set(
            wordsNeedingEnglish(
                in: limited,
                replacementLimit: replacementLimit,
                isFamiliar: isFamiliar
            )
        )
        let mutable = NSMutableString(string: limited)
        for match in wordMatches(in: limited).reversed() {
            let key = normalized(match.word)
            guard replaceable.contains(key),
                  let english = englishByDanishWord[key]
                    .map(cleanEnglishWord),
                  !english.isEmpty,
                  normalized(english) != key else {
                continue
            }
            mutable.replaceCharacters(in: match.range, with: english)
        }
        return mutable as String
    }

    private func wordMatches(
        in text: String
    ) -> [(word: String, range: NSRange)] {
        let range = NSRange(text.startIndex..., in: text)
        return Self.wordExpression.matches(in: text, range: range).compactMap {
            guard let swiftRange = Range($0.range, in: text) else {
                return nil
            }
            return (String(text[swiftRange]), $0.range)
        }
    }

    private func normalized(_ word: String) -> String {
        word.lowercased().trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters)
        )
    }

    private func cleanEnglishWord(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(.punctuationCharacters)
            )
    }

    private func completeWords(in text: String, limit: Int) -> String {
        let words = text.split(whereSeparator: \Character.isWhitespace)
        let selected = words.prefix(limit).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;:-"))
        guard !selected.isEmpty else {
            return ""
        }
        if selected.last.map({ ".!?".contains($0) }) == true {
            return selected
        }
        return selected + "."
    }
}
