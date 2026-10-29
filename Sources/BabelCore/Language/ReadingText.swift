import Foundation
import NaturalLanguage

/// Reading units keep Danish diacritics and alphanumeric names such as A2B.
/// Pure numbers are displayed verbatim rather than sent for word meanings.
public enum ReadingText {
    private static let pattern = try! NSRegularExpression(pattern: #"(?=[\p{L}\p{M}\p{N}]*\p{L})[\p{L}\p{M}\p{N}]+(?:['’\-][\p{L}\p{M}\p{N}]+)*"#)
    public static func words(in text: String) -> [String] {
        if text.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) {
            let tokenizer = NLTokenizer(unit: .word); tokenizer.string = text; tokenizer.setLanguage(.simplifiedChinese)
            var words: [String] = []
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                let word = String(text[range])
                if word.unicodeScalars.contains(where: CharacterSet.letters.contains) { words.append(word) }
                return true
            }
            return words
        }
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}
