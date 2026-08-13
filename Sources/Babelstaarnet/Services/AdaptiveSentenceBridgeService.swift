import Foundation

struct AdaptiveSentenceBridge: Equatable, Sendable {
    let text: String
    let englishTokenIndexes: [Int]
}

enum LanguageTransferState: Equatable, Sendable {
    case unknown
    case learning
    case testing
    case known

    static func forKnowledgeLevel(_ level: Int) -> Self {
        switch level {
        case ...0: .unknown
        case 1...2: .learning
        case 3: .testing
        default: .known
        }
    }
}

enum AdaptiveMeaningCoveragePolicy {
    /// Add only the English needed to keep the Danish sentence usable. Easy
    /// text stays nearly Danish-only; unfamiliar text receives more anchors
    /// without ever becoming a parallel English sentence.
    static func englishAnchorLimit(
        totalWordCount: Int,
        wordsNeedingSupport: Int
    ) -> Int {
        let total = max(1, totalWordCount)
        let unfamiliar = max(0, wordsNeedingSupport)
        guard unfamiliar > 0 else {
            return 0
        }
        if unfamiliar <= 2 {
            return unfamiliar
        }

        let unfamiliarShare = Double(unfamiliar) / Double(total)
        if unfamiliarShare <= 0.25 {
            return 2
        }
        if unfamiliarShare <= 0.50 {
            return min(3, unfamiliar)
        }
        return min(5, unfamiliar)
    }
}

/// The Danish words an anchor is never worth spending on.
///
/// A gloss is for a word the reader may not know. Danish's closed classes —
/// articles, pronouns, prepositions, conjunctions, and the auxiliary and copula
/// verbs — are the first fifty words of the language, so a reader who needs
/// them glossed cannot read the sentence they appear in either way. They are
/// also where word-at-a-time translation is least trustworthy, because their
/// English equivalent is decided by the construction around them rather than by
/// the word: asked on its own, "er" came back as "no".
///
/// Both costs land at once, because these are the words that appear in every
/// sentence. A line reading "Det er en betingelse for, at CPR-kontoret kan
/// tildele" spent two of its three anchors on "er" and "en" and had one left
/// for "betingelse", which is the only word in it a learner is likely to want.
///
/// Asking for all English overrides this: that is a direct request for the
/// translation rather than for support, and it is answered in full.
enum DanishFunctionWords {
    static func contains(_ normalizedWord: String) -> Bool {
        words.contains(normalizedWord)
    }

    private static let words: Set<String> = [
        // Articles and determiners
        "en", "et", "den", "det", "de", "denne", "dette", "disse",
        // Conjunctions and subordinators
        "og", "eller", "men", "som", "at", "når", "da", "hvis", "fordi",
        "mens", "end", "både", "samt",
        // Prepositions
        "i", "på", "til", "af", "for", "med", "om", "ved", "fra", "over",
        "under", "efter", "før", "mod", "hos", "uden", "mellem", "gennem",
        "omkring", "ind", "ud",
        // Pronouns and possessives
        "jeg", "du", "han", "hun", "vi", "dig", "mig", "sig", "os", "jer",
        "dem", "min", "mit", "din", "dit", "sin", "sit", "vores", "deres",
        "hans", "hendes", "man", "der", "hvad", "hvem", "hvor", "hvilken",
        // Auxiliary and copula verbs
        "er", "var", "været", "har", "havde", "haft", "være", "blive",
        "bliver", "blev", "blevet", "kan", "kunne", "skal", "skulle",
        "vil", "ville", "må", "måtte", "bør"
    ]
}

struct AdaptiveSentenceBridgeService {
    private static let englishStart = "\u{E000}"
    private static let englishEnd = "\u{E001}"
    private static let danishLocale = Locale(identifier: "da_DK")
    private static let wordTrimmingCharacters =
        CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    private static let wordExpression = try! NSRegularExpression(
        pattern: #"[\p{L}]+(?:['’-][\p{L}]+)*"#
    )

    func wordsNeedingEnglish(
        in danishText: String,
        wordLimit: Int = 20,
        stateForWord: (String) -> LanguageTransferState
    ) -> [String] {
        var seen = Set<String>()
        return wordMatches(in: danishText).compactMap { match in
            let word = normalized(match.word)
            let state = stateForWord(word)
            guard !word.isEmpty,
                  state == .unknown || state == .learning,
                  seen.insert(word).inserted else {
                return nil
            }
            return word
        }.prefix(max(0, wordLimit)).map { $0 }
    }

    func bridge(
        danishSentence: String,
        englishByDanishWord: [String: String],
        focusWord: String,
        focusOccurrence: Int = 0,
        stateForWord: (String) -> LanguageTransferState,
        wordLimit: Int = 20,
        replacementLimit: Int? = nil,
        glossesEveryWord: Bool = false
    ) -> AdaptiveSentenceBridge {
        let compact = danishSentence
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else {
            return AdaptiveSentenceBridge(text: "", englishTokenIndexes: [])
        }

        let contextual = contextWindow(
            in: compact,
            around: focusWord,
            occurrence: focusOccurrence,
            wordLimit: wordLimit
        )
        let normalizedFocus = normalized(focusWord)
        let matches = wordMatches(in: contextual)
        let eligibleIndexes = matches.indices.filter { index in
            let key = normalized(matches[index].word)
            let state = stateForWord(key)
            // The word under the pointer is always answerable, whatever class
            // it belongs to: the reader is asking about that one. The
            // exclusion applies to the rest of the line, which is where the
            // budget gets spent on words nobody asked about.
            guard glossesEveryWord
                || key == normalizedFocus
                || !DanishFunctionWords.contains(key) else {
                return false
            }
            guard state == .unknown || state == .learning,
                  let rawEnglish = englishByDanishWord[key],
                  let english = conciseEnglish(rawEnglish) else {
                return false
            }
            return normalized(english) != key
        }
        var seenConcepts = Set<String>()
        let conceptIndexes = eligibleIndexes.filter { index in
            seenConcepts.insert(normalized(matches[index].word)).inserted
        }
        let focusIndexes = eligibleIndexes.filter {
            normalized(matches[$0].word) == normalizedFocus
        }
        let focusIndex = focusIndexes.isEmpty
            ? nil
            : focusIndexes[
                min(max(0, focusOccurrence), focusIndexes.count - 1)
            ]
        let budget = replacementLimit.map { max(0, $0) }
            ?? AdaptiveMeaningCoveragePolicy.englishAnchorLimit(
                totalWordCount: matches.count,
                wordsNeedingSupport: seenConcepts.count
            )
        var selectedIndexes = focusIndex.map { budget > 0 ? [$0] : [] } ?? []
        let remaining = conceptIndexes
            .filter { index in
                guard let focusIndex else {
                    return true
                }
                return normalized(matches[index].word)
                    != normalized(matches[focusIndex].word)
            }
            .sorted { left, right in
                let leftPriority = supportPriority(
                    for: stateForWord(normalized(matches[left].word))
                )
                let rightPriority = supportPriority(
                    for: stateForWord(normalized(matches[right].word))
                )
                return leftPriority == rightPriority
                    ? left < right
                    : leftPriority < rightPriority
            }
        for index in remaining where selectedIndexes.count < budget {
            selectedIndexes.append(index)
        }
        let selected = Set(selectedIndexes)

        let mutable = NSMutableString(string: contextual)
        for index in matches.indices.reversed() {
            guard selected.contains(index) else {
                continue
            }
            let match = matches[index]
            let key = normalized(match.word)
            guard let rawEnglish = englishByDanishWord[key],
                  let english = conciseEnglish(rawEnglish),
                  normalized(english) != key else {
                continue
            }
            let replacement: String
            switch stateForWord(key) {
            case .unknown, .learning:
                replacement = "\(match.word) \(markedEnglish(english))"
            case .testing, .known:
                continue
            }
            mutable.replaceCharacters(in: match.range, with: replacement)
        }
        return annotatedBridge(from: mutable as String)
    }

    private func contextWindow(
        in text: String,
        around focusWord: String,
        occurrence: Int,
        wordLimit: Int
    ) -> String {
        let matches = wordMatches(in: text)
        let limit = max(1, wordLimit)
        guard matches.count > limit else {
            return completeSentence(text)
        }

        let focus = normalized(focusWord)
        let focusIndexes = matches.indices.filter {
            normalized(matches[$0].word) == focus
        }
        let focusIndex: Int
        if focusIndexes.isEmpty {
            focusIndex = 0
        } else {
            focusIndex = focusIndexes[min(max(0, occurrence), focusIndexes.count - 1)]
        }
        let preferredStart = focusIndex - limit / 2
        let start = min(max(0, preferredStart), matches.count - limit)
        let end = start + limit - 1
        let range = NSRange(
            location: matches[start].range.location,
            length: NSMaxRange(matches[end].range)
                - matches[start].range.location
        )
        let selected = (text as NSString).substring(with: range)
        return completeSentence(selected)
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
        word.lowercased(with: Self.danishLocale)
            .trimmingCharacters(
                in: Self.wordTrimmingCharacters
            )
    }

    private func conciseEnglish(_ value: String) -> String? {
        let compact = value
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(.punctuationCharacters)
            )
        let concise = compact.split(whereSeparator: \Character.isWhitespace)
            .prefix(4)
            .joined(separator: " ")
        return concise.isEmpty ? nil : concise
    }

    private func supportPriority(for state: LanguageTransferState) -> Int {
        switch state {
        case .unknown: 0
        case .learning: 1
        case .testing, .known: 2
        }
    }

    private func markedEnglish(_ value: String) -> String {
        Self.englishStart + value + Self.englishEnd
    }

    private func annotatedBridge(from markedText: String) -> AdaptiveSentenceBridge {
        var insideEnglish = false
        var tokens: [String] = []
        var englishIndexes: [Int] = []

        for rawToken in markedText.split(
            whereSeparator: \Character.isWhitespace
        ) {
            var token = String(rawToken)
            if token.contains(Self.englishStart) {
                insideEnglish = true
                token = token.replacingOccurrences(
                    of: Self.englishStart,
                    with: ""
                )
            }
            let isEnglish = insideEnglish
            if token.contains(Self.englishEnd) {
                token = token.replacingOccurrences(
                    of: Self.englishEnd,
                    with: ""
                )
                insideEnglish = false
            }
            guard !token.isEmpty else {
                continue
            }
            if isEnglish {
                englishIndexes.append(tokens.count)
            }
            tokens.append(token)
        }
        return AdaptiveSentenceBridge(
            text: tokens.joined(separator: " "),
            englishTokenIndexes: englishIndexes
        )
    }

    private func completeSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return ""
        }
        if trimmed.last.map({ ".!?".contains($0) }) == true {
            return trimmed
        }
        return trimmed.trimmingCharacters(
            in: CharacterSet(charactersIn: ",;:-")
        ) + "."
    }
}
