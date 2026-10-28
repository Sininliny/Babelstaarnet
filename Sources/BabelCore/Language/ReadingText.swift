import Foundation

/// Reading units keep Danish diacritics and alphanumeric names such as A2B.
/// Pure numbers are displayed verbatim rather than sent for word meanings.
public enum ReadingText {
    private static let pattern = try! NSRegularExpression(pattern: #"(?=[\p{L}\p{M}\p{N}]*\p{L})[\p{L}\p{M}\p{N}]+(?:['’\-][\p{L}\p{M}\p{N}]+)*"#)
    public static func words(in text: String) -> [String] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}
