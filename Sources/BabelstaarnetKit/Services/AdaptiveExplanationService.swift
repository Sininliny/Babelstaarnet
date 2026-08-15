import BabelCore
import Foundation

struct AdaptiveExplanation: Equatable, Sendable {
    let primaryText: String
    let englishSupport: String?
    let englishIsExpanded: Bool

    init(
        primaryText: String,
        englishSupport: String?,
        englishIsExpanded: Bool
    ) {
        self.primaryText = primaryText
        self.englishSupport = englishSupport
        self.englishIsExpanded = englishIsExpanded
    }
}

/// The meaning a hover is owed even while the reader is being quietly tested.
struct PassiveWordMeaningPolicy: Sendable {
    private let language: SourceLanguage
    private let target: TargetLanguage

    init(language: SourceLanguage, target: TargetLanguage) {
        self.language = language
        self.target = target
    }

    func directMeaning(
        sourceWord: String,
        translation englishTranslation: String,
        knowledgeLevel: Int
    ) -> String? {
        // A focused hover is a request for meaning, even while the learner is
        // being quietly tested. Only a known state removes this safety net.
        guard (0...3).contains(knowledgeLevel) else {
            return nil
        }

        let compact = englishTranslation.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty,
              normalized(compact) != normalized(sourceWord) else {
            return nil
        }

        let words = compact.split(whereSeparator: \Character.isWhitespace)
        guard words.count > 12 else {
            return compact
        }

        // Prefer a complete, useful phrase over a chopped dictionary fragment.
        // Bubble text deliberately uses no ellipsis.
        var selected = Array(words.prefix(12))
        while selected.count > 6,
              let last = selected.last,
              target.danglingWords.contains(normalized(String(last))) {
            selected.removeLast()
        }
        return selected.joined(separator: " ")
    }

    private func normalized(_ value: String) -> String {
        language.normalized(value)
    }
}

struct AdaptiveExplanationService: Sendable {
    private let language: SourceLanguage

    init(language: SourceLanguage) {
        self.language = language
    }

    func explanation(
        bridgeText: String,
        englishMeaning: String,
        expandedEnglish: String,
        expandEnglish: Bool
    ) -> AdaptiveExplanation {
        // The bridge arrives already bounded to one sentence, so this is a
        // ceiling on the pathological case rather than the usual cut: the
        // English standing in for Danish words can be four tokens where the
        // Danish was one, and a bubble is still a bubble. Counting raw tokens
        // at the old limit of 36 was cutting ordinary sentences that the
        // bridge had deliberately kept whole.
        let bridge = brief(bridgeText, wordLimit: 64)
        let meaning = englishMeaning.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let expanded = brief(expandedEnglish, wordLimit: 24)

        if bridge.isEmpty {
            return AdaptiveExplanation(
                primaryText: meaning.isEmpty
                    ? "No local explanation found."
                    : language.meansPhrase(meaning),
                englishSupport: expandEnglish && !expanded.isEmpty
                    ? expanded
                    : nil,
                englishIsExpanded: expandEnglish
            )
        }

        return AdaptiveExplanation(
            primaryText: bridge,
            englishSupport: expandEnglish && !expanded.isEmpty
                ? expanded
                : nil,
            englishIsExpanded: expandEnglish
        )
    }

    private func brief(_ text: String, wordLimit: Int) -> String {
        let compact = text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else {
            return ""
        }
        let words = compact.split(whereSeparator: \Character.isWhitespace)
        guard words.count > wordLimit else {
            return compact
        }
        let selected = words.prefix(wordLimit).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;:-"))
        return selected + "."
    }
}
