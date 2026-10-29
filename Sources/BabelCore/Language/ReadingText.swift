import Foundation
import NaturalLanguage

/// Reading units keep Danish diacritics and alphanumeric names such as A2B.
/// Pure numbers are displayed verbatim rather than sent for word meanings.
public enum ReadingText {
    private static let cjkSpacing = try! NSRegularExpression(pattern: #"(?<=[\u3400-\u9fff\uf900-\ufaff])\s+(?=[\u3400-\u9fff\uf900-\ufaff])"#)
    public static func compactCjkSpacing(_ text: String) -> String {
        cjkSpacing.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }
    /// Tokenize the compact Chinese reading but return ranges in the untouched
    /// Vision string, so word boxes continue to refer to the original pixels.
    public static func ocrWordRanges(in text: String, language: NLLanguage) -> [Range<String.Index>] {
        let compact = compactCjkSpacing(text)
        let tokenizer = NLTokenizer(unit: .word); tokenizer.string = compact; tokenizer.setLanguage(language)
        var offsets: [String.Index] = []
        let removed = cjkSpacing.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
        var offset = 0
        for index in text.indices {
            let length = String(text[index]).utf16.count
            if !removed.contains(where: { NSLocationInRange(offset, $0) }) { offsets.append(contentsOf: repeatElement(index, count: length)) }
            offset += length
        }
        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: compact.startIndex..<compact.endIndex) { range, _ in
            let ns = NSRange(range, in: compact)
            if ns.length > 0, NSMaxRange(ns) <= offsets.count {
                ranges.append(offsets[ns.location]..<text.index(after: offsets[NSMaxRange(ns)-1]))
            }
            return true
        }
        return ranges
    }
    private static let pattern = try! NSRegularExpression(pattern: #"(?=[\p{L}\p{M}\p{N}]*\p{L})[\p{L}\p{M}\p{N}]+(?:['’\-][\p{L}\p{M}\p{N}]+)*"#)
    public static func words(in original: String) -> [String] {
        let text = compactCjkSpacing(original)
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
