import Foundation

@main
enum DictionaryServiceChecks {
    static func main() {
        let adaptive = DictionaryService().adaptiveEnglishGloss(
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
