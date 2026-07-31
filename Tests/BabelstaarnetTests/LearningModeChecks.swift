import Foundation

@main
enum LearningModeChecks {
    static func main() {
        precondition(TranslationMode.allCases == [.english, .none])
        precondition(
            ExplanationMode.allCases
                == [.beginner, .easyDanish, .english, .none]
        )
        precondition(TranslationMode.english.title == "Danish → English")
        precondition(TranslationMode.none.shortTitle == "No translation")
        precondition(ExplanationMode.beginner.badgeTitle == "BEGINNER")
        precondition(ExplanationMode.easyDanish.badgeTitle == "LET DANSK")
        precondition(ExplanationMode.english.badgeTitle == "ENGLISH")
        precondition(ExplanationMode.none.badgeTitle == nil)
        print("Independent translation and explanation checks passed")
    }
}
