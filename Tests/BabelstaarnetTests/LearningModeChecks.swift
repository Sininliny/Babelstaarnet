import Foundation

@main
enum LearningModeChecks {
    static func main() {
        precondition(TranslationMode.allCases == [.english, .none])
        precondition(
            ExplanationMode.allCases
                == [.adaptive, .beginner, .easyDanish, .english, .none]
        )
        precondition(TranslationMode.english.title == "Danish → English")
        precondition(TranslationMode.none.shortTitle == "No translation")
        precondition(ExplanationMode.adaptive.badgeTitle == nil)
        precondition(ExplanationMode.beginner.badgeTitle == nil)
        precondition(ExplanationMode.easyDanish.badgeTitle == nil)
        precondition(ExplanationMode.english.badgeTitle == nil)
        precondition(ExplanationMode.none.badgeTitle == nil)
        print("Independent translation and explanation checks passed")
    }
}
