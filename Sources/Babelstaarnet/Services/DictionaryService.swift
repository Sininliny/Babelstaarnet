import CoreServices
import Foundation

struct DictionaryService {
    func definition(for translatedWord: String, sourceWord: String) -> String {
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
            let fullDefinition = unmanaged.takeRetainedValue() as String
            return fullDefinition.truncatedDefinition()
        }

        return "“\(translatedWord)” is the English meaning of “\(sourceWord)”."
    }
}

private extension String {
    func truncatedDefinition(limit: Int = 320) -> String {
        let compact = replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard compact.count > limit else {
            return compact
        }
        let end = compact.index(compact.startIndex, offsetBy: limit)
        return String(compact[..<end]).trimmingCharacters(in: .whitespaces) + "…"
    }
}
