import CoreServices
import Foundation

struct DictionaryService {
    func adaptiveEnglishGloss(
        for translatedWord: String,
        sourceWord: String
    ) -> String {
        learnerGloss(
            for: translatedWord,
            sourceWord: sourceWord
        )
    }

    private func learnerGloss(
        for translatedWord: String,
        sourceWord: String
    ) -> String {
        let meaning = translatedWord.compacted
        guard !meaning.isEmpty else {
            return "No English meaning found."
        }
        let definition = fullDefinition(
            for: translatedWord,
            sourceWord: sourceWord
        )
        guard !definition.localizedCaseInsensitiveContains(
            "English meaning of"
        ) else {
            return "Means “\(meaning)”."
        }
        let sense = definition.learnerSense(
            wordLimit: 16
        )
        guard !sense.isEmpty else {
            return "Means “\(meaning)”."
        }
        return "“\(meaning)” — \(sense)"
    }

    private func fullDefinition(
        for translatedWord: String,
        sourceWord: String
    ) -> String {
        let candidates = dictionaryCandidates(for: translatedWord)
        guard !candidates.isEmpty else {
            return "English translation of “\(sourceWord)”."
        }

        for candidate in candidates {
            let length = (candidate as NSString).length
            if let unmanaged = DCSCopyTextDefinition(
                nil,
                candidate as CFString,
                CFRange(location: 0, length: length)
            ) {
                return unmanaged.takeRetainedValue() as String
            }
        }

        return "“\(translatedWord)” is the English meaning of “\(sourceWord)”."
    }

    private func dictionaryCandidates(for translatedWord: String) -> [String] {
        let phrase = translatedWord.compacted
            .trimmingCharacters(in: .punctuationCharacters)
        let words = phrase.split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            return []
        }
        let likelyHead: String
        if words.first?.lowercased() == "to", words.count > 1 {
            likelyHead = words[1]
        } else {
            likelyHead = words.last ?? phrase
        }
        var seen = Set<String>()
        return [likelyHead, phrase, words[0]].filter {
            !$0.isEmpty && seen.insert($0.lowercased()).inserted
        }
    }
}

private extension String {
    var compacted: String {
        replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func learnerSense(wordLimit: Int) -> String {
        var value = compacted
        if let partOfSpeech = value.range(
            of: #"\|\s*(?:(?:plural|mass|proper|auxiliary|modal)\s+)?(noun|verb|adjective|adverb|preposition|pronoun|conjunction|determiner|exclamation)\s+"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            value = String(value[partOfSpeech.upperBound...])
        }
        value = value.replacingOccurrences(
            of: #"^\s*\d+[a-z]?\s*"#,
            with: "",
            options: .regularExpression
        )
        if let nextSense = value.range(
            of: #"\s+\d+[a-z]?\s+"#,
            options: .regularExpression
        ) {
            value = String(value[..<nextSense.lowerBound])
        }
        if let example = value.firstIndex(of: ":") {
            value = String(value[..<example])
        }
        if let boundary = value.rangeOfCharacter(
            from: CharacterSet(charactersIn: ";.")
        ) {
            value = String(value[..<boundary.lowerBound])
        }
        return value.compacted.completeWords(limit: wordLimit)
    }

    func completeWords(limit: Int) -> String {
        let words = split(whereSeparator: \Character.isWhitespace)
        let selected = words.prefix(limit).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
