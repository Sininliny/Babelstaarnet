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
        replacementLimit: Int? = nil
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
        // Every word the reader cannot read is replaced. A cap made sense
        // while English was added beside the Danish: a few notes, and the
        // Danish still there to read. Substituting only some of them leaves
        // the rest stranded in a line that is no longer Danish either — the
        // reader gets "the period of reflection på 6 months fra time", which
        // is not readable in either language. What adapts is the profile:
        // words the reader knows stay Danish, and more of them do over time.
        let budget = replacementLimit.map { max(0, $0) } ?? eligibleIndexes.count
        var selectedIndexes = focusIndex.map { budget > 0 ? [$0] : [] } ?? []
        // Unlimited, every occurrence is replaced, not just the first of each
        // word: leaving the second one Danish would put the same word on the
        // line in both languages. A caller that asks for a fixed number is
        // spending anchors instead, and spends them on distinct words.
        let candidates = replacementLimit == nil
            ? eligibleIndexes
            : conceptIndexes
        let remaining = candidates
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
                // The English takes the word's place rather than being hung
                // underneath it. Keeping both meant the reader assembled the
                // sentence from two texts at once, reading a Danish line and a
                // row of footnotes against it; a word they cannot read is not
                // made readable by being left in place with a note attached.
                // Substituting gives them one line they can read straight
                // through, in Danish word order, with the words they do know
                // still in Danish.
                replacement = markedEnglish(
                    Self.matchingCase(
                        of: english,
                        to: match.word,
                        isSentenceStart: index == 0
                    )
                )
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

    /// Gives the English the case of the Danish it stands in for.
    ///
    /// Words are translated one at a time, so each comes back as though it
    /// opened a sentence. Standing in the middle of a line, a capital reads as
    /// a proper noun; standing at the start of one, a lower-case word reads as
    /// a fragment. The Danish it replaces settles both, and Danish capitalises
    /// proper nouns and sentence openings only — which is what makes this safe
    /// here and would not make it safe for German.
    static func matchingCase(
        of english: String,
        to danish: String,
        isSentenceStart: Bool = false
    ) -> String {
        guard let englishFirst = english.first,
              let danishFirst = danish.first else {
            return english
        }
        // Only the opening word takes a capital from the Danish. Elsewhere a
        // capitalised Danish word is a name or an acronym — "CPR-kontoret" —
        // and its English often begins with an article, so borrowing the
        // capital produced "The CPR office" in the middle of a line.
        if isSentenceStart {
            return danishFirst.isUppercase && englishFirst.isLowercase
                ? english.prefix(1).uppercased() + english.dropFirst()
                : english
        }
        if danishFirst.isLowercase, englishFirst.isUppercase {
            return english.prefix(1).lowercased() + english.dropFirst()
        }
        return english
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
