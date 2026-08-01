import Foundation

struct TranslationQualityService {
    func needsRetry(source: String, translation: String) -> Bool {
        let sourceKey = normalized(source)
        let translationKey = normalized(translation)
        return translationKey.isEmpty || sourceKey == translationKey
    }

    func bestTranslation(
        source: String,
        primary: String,
        lowercaseRetry: String? = nil
    ) -> String {
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

    func localFallback(for source: String) -> String? {
        let key = normalized(source)
        if let exact = Self.exactTranslations[key] {
            return exact
        }

        for (suffix, englishSuffix) in Self.compoundSuffixes
        where key.hasSuffix(suffix) && key.count > suffix.count {
            let split = key.index(key.endIndex, offsetBy: -suffix.count)
            let prefix = String(key[..<split])
            let englishPrefix = Self.exactTranslations[prefix]
                ?? readableASCII(prefix)
            guard let englishPrefix, !englishPrefix.isEmpty else {
                continue
            }
            return "\(englishPrefix) \(englishSuffix)"
        }
        return nil
    }

    private func normalized(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "ø", with: "oe")
            .replacingOccurrences(of: "å", with: "aa")
            .folding(options: [.diacriticInsensitive], locale: nil)
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(.punctuationCharacters)
            )
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

    private static let exactTranslations: [String: String] = [
        "avanceret": "advanced",
        "arkitektur": "architecture",
        "computer": "computer",
        "data": "data",
        "database": "database",
        "databaser": "databases",
        "netvaerk": "network",
        "orkestrering": "orchestration",
        "software": "software",
        "teknologi": "technology",
        "telemedicin": "telemedicine",
        "udvikling": "development",
        "web": "web",
        "webarkitektur": "web architecture"
    ]

    private static let compoundSuffixes: [(String, String)] = [
        ("arkitektur", "architecture"),
        ("orkestrering", "orchestration"),
        ("telemedicin", "telemedicine"),
        ("teknologi", "technology"),
        ("udvikling", "development"),
        ("databaser", "databases"),
        ("database", "database"),
        ("netvaerk", "network"),
        ("systemer", "systems"),
        ("system", "system")
    ]
}
