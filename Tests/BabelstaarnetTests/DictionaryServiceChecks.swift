import Foundation
@testable import BabelCore
@testable import BabelOCR
@testable import BabelTranslate
@testable import BabelLexicon
@testable import BabelSpeech
@testable import LanguageDanish
@testable import BabelstaarnetKit

@main
enum DictionaryServiceChecks {
    static func main() {
        let adaptive = DictionaryService(target: .english).adaptiveGloss(
            for: "natural resources",
            sourceWord: "naturressourcer"
        )
        precondition(adaptive.contains("natural resources"))
        precondition(!adaptive.contains("…"))
        precondition(!adaptive.contains("|"))
        precondition(
            !adaptive.localizedCaseInsensitiveContains("adjective")
        )
        precondition(adaptive.split(separator: " ").count <= 20)

        print("Adaptive English support checks passed")
    }
}
