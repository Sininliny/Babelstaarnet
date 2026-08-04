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
        replacementLimit: Int = 3
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
            return (state == .unknown || state == .learning)
                && englishByDanishWord[key] != nil
        }
        let budget = max(0, replacementLimit)
        var selectedIndexes = Array(eligibleIndexes.prefix(budget))
        let focusIndexes = eligibleIndexes.filter {
            normalized(matches[$0].word) == normalizedFocus
        }
        if budget > 0,
           !focusIndexes.isEmpty {
            let focusIndex = focusIndexes[
                min(max(0, focusOccurrence), focusIndexes.count - 1)
            ]
            if !selectedIndexes.contains(focusIndex) {
                if !selectedIndexes.isEmpty {
                    selectedIndexes.removeLast()
                }
                selectedIndexes.append(focusIndex)
            }
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
