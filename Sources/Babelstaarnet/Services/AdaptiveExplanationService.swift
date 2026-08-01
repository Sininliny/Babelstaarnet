import Foundation

struct AdaptiveExplanation: Equatable, Sendable {
    let primaryText: String
    let englishSupport: String?
    let familiarityLabel: String
    let englishIsExpanded: Bool
}

struct AdaptiveExplanationService {
    func explanation(
        easyDanish: String,
        englishMeaning: String,
        shortEnglish: String,
        fullEnglish: String,
        progress: LearnerWordProgress,
        expandEnglish: Bool,
        at date: Date = Date()
    ) -> AdaptiveExplanation {
        let mixed = brief(easyDanish, wordLimit: 20)
        let meaning = englishMeaning.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let short = brief(shortEnglish, wordLimit: 16)
        let full = brief(fullEnglish, wordLimit: 24)
        let selectedEnglish: String
        if expandEnglish, !full.isEmpty {
            selectedEnglish = full
        } else if !short.isEmpty {
            selectedEnglish = short
        } else if !meaning.isEmpty {
            selectedEnglish = "Means “\(meaning)”."
        } else {
            selectedEnglish = ""
        }

        if mixed.isEmpty {
            return AdaptiveExplanation(
                primaryText: meaning.isEmpty
                    ? "No local explanation found."
                    : "Betyder “\(meaning)”.",
                englishSupport: expandEnglish && !selectedEnglish.isEmpty
                    ? selectedEnglish
                    : nil,
                familiarityLabel: progress.level(at: date).title,
                englishIsExpanded: expandEnglish
            )
        }

        return AdaptiveExplanation(
            primaryText: mixed,
            englishSupport: expandEnglish && !selectedEnglish.isEmpty
                ? selectedEnglish
                : nil,
            familiarityLabel: progress.level(at: date).title,
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
