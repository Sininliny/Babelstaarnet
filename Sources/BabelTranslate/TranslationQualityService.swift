import BabelCore
import Foundation

/// Whether a translation is good enough to stand in place of the word it
/// replaced, and what to show instead when it is not.
///
/// Every table this consults belongs to the source language, so the judgement
/// is the same in any language and only the evidence changes.
public struct TranslationQualityService: Sendable {
    private let language: SourceLanguage

    public init(language: SourceLanguage) {
        self.language = language
    }

    public func needsRetry(source: String, translation: String) -> Bool {
        let sourceKey = language.folded(source)
        let translationKey = language.folded(translation)
        if translationKey.isEmpty || sourceKey == translationKey {
            return true
        }
        if let accepted = language.acceptedGlosses[sourceKey],
           !accepted.contains(translationKey) {
            return true
        }
        return false
    }

    public func bestTranslation(
        source: String,
        primary: String,
        lowercaseRetry: String? = nil
    ) -> String {
        // A closed-class word is answered from the table rather than by the
        // translator. Asked on its own, Danish "er" comes back as "no" — and
        // once the target language stands in place of the source rather than
        // beside it, a wrong answer is not a wrong note next to a readable
        // word, it is the only thing left. These classes are small, closed,
        // and stable, so the citation form can simply be written down.
        let sourceKey = language.folded(source)
        if let curated = language.closedClassGlosses[sourceKey] {
            // Where a word has an explicit accepted set, that set still wins:
            // it records the readings a translator may legitimately return, and
            // "for meget" really is "too much". The curated form is what the
            // word falls back to, not what it is pinned to.
            if let accepted = language.acceptedGlosses[sourceKey],
               accepted.contains(language.folded(primary)) {
                return cleaned(primary)
            }
            return curated
        }
        if let lowercaseRetry,
           !needsRetry(source: source, translation: lowercaseRetry) {
            return cleaned(lowercaseRetry)
        }
        if !needsRetry(source: source, translation: primary) {
            return cleaned(primary)
        }
        if let local = localFallback(for: source) {
            return local
        }
        return cleaned(primary)
    }

    public func localFallback(for source: String) -> String? {
        let key = language.folded(source)
        if let exact = language.exactGlosses[key] {
            return exact
        }

        for compound in language.compoundSuffixes
        where key.hasSuffix(compound.suffix)
            && key.count > compound.suffix.count {
            let split = key.index(
                key.endIndex,
                offsetBy: -compound.suffix.count
            )
            let prefix = String(key[..<split])
            let glossedPrefix = language.exactGlosses[prefix]
                ?? readableASCII(prefix)
            guard let glossedPrefix, !glossedPrefix.isEmpty else {
                continue
            }
            return "\(glossedPrefix) \(compound.gloss)"
        }
        return nil
    }

    private func cleaned(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readableASCII(_ value: String) -> String? {
        guard value.unicodeScalars.allSatisfy({ $0.isASCII }),
              value.rangeOfCharacter(from: .letters) != nil else {
            return nil
        }
        return value
    }
}
