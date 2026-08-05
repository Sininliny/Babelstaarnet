import Foundation

struct AdaptiveExplanation: Equatable, Sendable {
    let primaryText: String
    let englishSupport: String?
    let englishIsExpanded: Bool
}

enum PassiveWordMeaningPolicy {
    static func directEnglishMeaning(
        sourceWord: String,
        englishTranslation: String,
        knowledgeLevel: Int
    ) -> String? {
        guard (0...2).contains(knowledgeLevel) else {
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
        return words.prefix(6).joined(separator: " ")
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased(with: Locale(identifier: "da_DK"))
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(.punctuationCharacters)
            )
    }
}

struct AdaptiveExplanationService {
    func explanation(
        bridgeText: String,
        englishMeaning: String,
        expandedEnglish: String,
        expandEnglish: Bool
    ) -> AdaptiveExplanation {
        // A sentence bridge contains at most 20 Danish words and three short
        // English glosses. Keep the complete Danish context instead of
        // truncating it because gloss tokens increased the raw word count.
        let bridge = brief(bridgeText, wordLimit: 36)
        let meaning = englishMeaning.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let expanded = brief(expandedEnglish, wordLimit: 24)

        if bridge.isEmpty {
            return AdaptiveExplanation(
                primaryText: meaning.isEmpty
                    ? "No local explanation found."
                    : "Betyder “\(meaning)”.",
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
