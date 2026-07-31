import CoreServices
import Foundation

struct DictionaryService {
    func definition(for translatedWord: String, sourceWord: String) -> String {
        fullDefinition(
            for: translatedWord,
            sourceWord: sourceWord
        ).truncatedDefinition()
    }

    func beginnerExplanation(
        for translatedWord: String,
        sourceWord: String
    ) -> String {
        fullDefinition(
            for: translatedWord,
            sourceWord: sourceWord
        ).beginnerGloss()
    }

    private func fullDefinition(
        for translatedWord: String,
        sourceWord: String
    ) -> String {
        let cleaned = translatedWord
            .components(separatedBy: .whitespacesAndNewlines)
            .first?
            .trimmingCharacters(in: .punctuationCharacters) ?? translatedWord

        guard !cleaned.isEmpty else {
            return "English translation of “\(sourceWord)”."
        }

        let length = (cleaned as NSString).length
        if let unmanaged = DCSCopyTextDefinition(
            nil,
            cleaned as CFString,
            CFRange(location: 0, length: length)
        ) {
            return unmanaged.takeRetainedValue() as String
        }

        return "“\(translatedWord)” is the English meaning of “\(sourceWord)”."
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

    func truncatedDefinition(limit: Int = 320) -> String {
        compacted.truncated(to: limit)
    }

    func beginnerGloss(limit: Int = 150) -> String {
        let compact = compacted
        let firstSentence = compact.firstSentence ?? compact
        return firstSentence.truncated(to: limit)
    }

    var firstSentence: String? {
        let boundaries = CharacterSet(charactersIn: ".!?")
        guard let boundary = rangeOfCharacter(from: boundaries) else {
            return isEmpty ? nil : self
        }
        return String(self[...boundary.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            + String(self[boundary.lowerBound])
    }

    func truncated(to limit: Int) -> String {
        guard count > limit else {
            return self
        }
        let end = index(startIndex, offsetBy: limit)
        return String(self[..<end])
            .trimmingCharacters(in: .whitespaces) + "…"
    }
}
