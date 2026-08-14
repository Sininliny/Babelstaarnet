import Foundation

struct TranslationQualityService {
    func needsRetry(source: String, translation: String) -> Bool {
        let sourceKey = normalized(source)
        let translationKey = normalized(translation)
        if translationKey.isEmpty || sourceKey == translationKey {
            return true
        }
        if let accepted = Self.acceptedTranslations[sourceKey],
           !accepted.contains(translationKey) {
            return true
        }
        return false
    }

    func bestTranslation(
        source: String,
        primary: String,
        lowercaseRetry: String? = nil
    ) -> String {
        // A closed-class word is answered from the table rather than by the
        // translator. Asked on its own, "er" comes back as "no" — and once
        // English stands in place of the Danish rather than beside it, a wrong
        // answer is not a wrong note next to a readable word, it is the only
        // thing left. These classes are small, closed, and stable, so the
        // citation form can simply be written down.
        if let curated = Self.closedClassTranslations[normalized(source)] {
            // Where a word has an explicit accepted set, that set still wins:
            // it records the readings a translator may legitimately return, and
            // "for meget" really is "too much". The curated form is what the
            // word falls back to, not what it is pinned to.
            if let accepted = Self.acceptedTranslations[normalized(source)],
               accepted.contains(normalized(primary)) {
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

    /// Danish's closed classes, in the folded ASCII form `normalized` produces.
    ///
    /// A preposition has no single English equivalent — "på" is on, at, or in
    /// depending on what follows — so these are citation forms, right often
    /// rather than always. That is still a different order of accuracy from
    /// what a sentence-trained model returns for a word handed to it alone.
    private static let closedClassTranslations: [String: String] = [
        // Copula, auxiliaries, and modals
        "er": "is", "var": "was", "vaeret": "been", "vaere": "be",
        "har": "has", "havde": "had", "haft": "had",
        "blive": "become", "bliver": "becomes", "blev": "became",
        "blevet": "become", "kan": "can", "kunne": "could",
        "skal": "must", "skulle": "should", "vil": "will",
        "ville": "would", "maa": "may", "maatte": "had to", "boer": "should",
        // Articles and determiners
        "en": "a", "et": "a", "den": "the", "det": "it", "de": "they",
        "denne": "this", "dette": "this", "disse": "these",
        // Conjunctions and subordinators
        "og": "and", "eller": "or", "men": "but", "som": "which",
        "at": "that", "naar": "when", "da": "when", "hvis": "if",
        "fordi": "because", "mens": "while", "end": "than",
        "baade": "both", "samt": "and",
        // Prepositions
        "i": "in", "paa": "on", "til": "to", "af": "of", "for": "for",
        "med": "with", "om": "about", "ved": "at", "fra": "from",
        "over": "over", "under": "under", "efter": "after",
        "foer": "before", "mod": "towards", "hos": "with",
        "uden": "without", "mellem": "between", "gennem": "through",
        "omkring": "around", "ind": "in", "ud": "out",
        // Pronouns and possessives
        "jeg": "I", "du": "you", "han": "he", "hun": "she", "vi": "we",
        "dig": "you", "mig": "me", "sig": "itself", "os": "us",
        "jer": "you", "dem": "them", "min": "my", "mit": "my",
        "din": "your", "dit": "your", "sin": "its", "sit": "its",
        "vores": "our", "deres": "their", "hans": "his",
        "hendes": "her", "man": "one", "der": "there", "hvad": "what",
        "hvem": "who", "hvor": "where", "hvilken": "which",
        "ikke": "not"
    ]

    private static let exactTranslations: [String: String] = [
        "avanceret": "advanced",
        "arkitektur": "architecture",
        "computer": "computer",
        "data": "data",
        "database": "database",
        "databaser": "databases",
        "for": "for",
        "netvaerk": "network",
        "orkestrering": "orchestration",
        "software": "software",
        "teknologi": "technology",
        "telemedicin": "telemedicine",
        "udvikling": "development",
        "web": "web",
        "webarkitektur": "web architecture"
    ]

    // Context-free translation occasionally turns the very common Danish
    // preposition "for" into "no". These are the useful English readings a
    // single-word bridge may safely present; anything else falls back locally.
    private static let acceptedTranslations: [String: Set<String>] = [
        "for": ["for", "too", "because", "ago"]
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
