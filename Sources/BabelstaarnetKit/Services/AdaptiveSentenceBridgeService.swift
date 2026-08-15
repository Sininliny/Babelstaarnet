import BabelCore
import Foundation

struct AdaptiveSentenceBridge: Equatable, Sendable {
    let text: String
    let englishTokenIndexes: [Int]
    /// The tokens standing in for the word under the pointer, when that word
    /// was one of the replaced ones. Without it the sentence panel cannot show
    /// which of its words answers the question that was asked: the reader
    /// points at "læringsmiljøer" and the sentence says "learning
    /// environments" somewhere in the middle of a line, with nothing to
    /// connect the two panels to each other.
    let focusEnglishTokenIndexes: [Int]

    init(
        text: String,
        englishTokenIndexes: [Int],
        focusEnglishTokenIndexes: [Int] = []
    ) {
        self.text = text
        self.englishTokenIndexes = englishTokenIndexes
        self.focusEnglishTokenIndexes = focusEnglishTokenIndexes
    }
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

struct AdaptiveSentenceBridgeService: Sendable {
    private let language: SourceLanguage
    private let boundary: SentenceBoundary

    init(language: SourceLanguage) {
        self.language = language
        self.boundary = language.sentenceBoundary
    }

    private static let englishStart = "\u{E000}"
    private static let englishEnd = "\u{E001}"
    // The word that was asked about is marked apart from the rest of the
    // English, because the panel showing the sentence has to be able to point
    // back at the word the panel above it is answering.
    private static let focusStart = "\u{E002}"
    private static let focusEnd = "\u{E003}"
    private static let wordTrimmingCharacters =
        CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    private static let wordExpression = try! NSRegularExpression(
        pattern: #"[\p{L}]+(?:['’-][\p{L}]+)*"#
    )
    /// Where a Danish sentence pauses, and so where it can be cut without
    /// leaving half a clause behind.
    private static let clauseSeparators: Set<unichar> = Set(
        ",;:—–()[]".unicodeScalars.map { unichar($0.value) }
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
        wordLimit: Int = 36,
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
                    ),
                    isFocus: index == focusIndex
                )
            case .testing, .known:
                continue
            }
            mutable.replaceCharacters(in: match.range, with: replacement)
        }
        return annotatedBridge(from: mutable as String)
    }

    /// The text the bridge rewrites: the sentence the pointed-at word belongs
    /// to, kept whole wherever it fits.
    ///
    /// A window measured only in words stopped wherever the count ran out, so
    /// the reader was handed a line that began after the subject and ended
    /// before the verb. The sentence is the unit carrying the word order this
    /// is meant to teach, so it survives intact; one long enough to still need
    /// cutting is cut where the sentence itself pauses rather than mid-phrase.
    private func contextWindow(
        in text: String,
        around focusWord: String,
        occurrence: Int,
        wordLimit: Int
    ) -> String {
        let sentence = focusedSentence(
            in: text,
            around: focusWord,
            occurrence: occurrence
        )
        let matches = wordMatches(in: sentence)
        let limit = max(1, wordLimit)
        guard matches.count > limit else {
            return completeSentence(sentence)
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
        let selected = (sentence as NSString).substring(
            with: clauseBounded(
                range,
                around: matches[focusIndex].range,
                in: sentence
            )
        )
        return completeSentence(selected)
    }

    /// Narrows text holding several sentences to the one that was pointed at.
    ///
    /// Text with no word to point at is left alone: a word bridge arrives here
    /// as a whole short Danish explanation, and keeping only its first sentence
    /// would drop the half that explains the word.
    private func focusedSentence(
        in text: String,
        around focusWord: String,
        occurrence: Int
    ) -> String {
        guard boundary.sentenceRanges(in: text).count > 1 else {
            return text
        }
        let matches = wordMatches(in: text)
        let focus = normalized(focusWord)
        let focusIndexes = matches.indices.filter {
            normalized(matches[$0].word) == focus
        }
        guard !focusIndexes.isEmpty else {
            return text
        }
        let index = focusIndexes[
            min(max(0, occurrence), focusIndexes.count - 1)
        ]
        let sentence = boundary.sentenceRange(
            in: text,
            containing: matches[index].range.location
        )
        return (text as NSString)
            .substring(with: sentence)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Moves the edges of a word window onto the sentence's own pauses, so a
    /// cut sentence still reads as a phrase instead of stopping mid-thought.
    private func clauseBounded(
        _ range: NSRange,
        around focus: NSRange,
        in text: String
    ) -> NSRange {
        let source = text as NSString
        var start = range.location
        var end = NSMaxRange(range)

        var index = focus.location - 1
        while index >= range.location {
            if Self.clauseSeparators.contains(
                source.character(at: index)
            ) {
                start = index + 1
                break
            }
            index -= 1
        }
        // Searched from the far edge inwards, so the window gives up as little
        // of the sentence as a complete phrase allows.
        index = end - 1
        while index >= NSMaxRange(focus) {
            if Self.clauseSeparators.contains(
                source.character(at: index)
            ) {
                end = index
                break
            }
            index -= 1
        }
        while start < end,
              let scalar = UnicodeScalar(source.character(at: start)),
              CharacterSet.whitespaces.contains(scalar) {
            start += 1
        }
        guard start < end, start <= focus.location else {
            return range
        }
        return NSRange(location: start, length: end - start)
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
        language.lowercased(word)
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

    private func markedEnglish(
        _ value: String,
        isFocus: Bool = false
    ) -> String {
        isFocus
            ? Self.focusStart + value + Self.focusEnd
            : Self.englishStart + value + Self.englishEnd
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
        var insideFocus = false
        var tokens: [String] = []
        var englishIndexes: [Int] = []
        var focusIndexes: [Int] = []

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
            if token.contains(Self.focusStart) {
                insideEnglish = true
                insideFocus = true
                token = token.replacingOccurrences(
                    of: Self.focusStart,
                    with: ""
                )
            }
            let isEnglish = insideEnglish
            let isFocus = insideFocus
            if token.contains(Self.englishEnd) {
                token = token.replacingOccurrences(
                    of: Self.englishEnd,
                    with: ""
                )
                insideEnglish = false
            }
            if token.contains(Self.focusEnd) {
                token = token.replacingOccurrences(
                    of: Self.focusEnd,
                    with: ""
                )
                insideEnglish = false
                insideFocus = false
            }
            guard !token.isEmpty else {
                continue
            }
            if isEnglish {
                englishIndexes.append(tokens.count)
            }
            if isFocus {
                focusIndexes.append(tokens.count)
            }
            tokens.append(token)
        }
        return AdaptiveSentenceBridge(
            text: tokens.joined(separator: " "),
            englishTokenIndexes: englishIndexes,
            focusEnglishTokenIndexes: focusIndexes
        )
    }

    private func completeSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return ""
        }
        if trimmed.last.map({ ".!?…".contains($0) }) == true {
            return trimmed
        }
        return trimmed.trimmingCharacters(
            in: CharacterSet(charactersIn: ",;:-")
        ) + "."
    }
}
