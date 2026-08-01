import Foundation

@main
enum DictionaryServiceChecks {
    static func main() {
        let target = "unfindable-english-meaning"
        let source = "uoversættelig"
        let result = DictionaryService().definition(
            for: target,
            sourceWord: source
        )

        precondition(!result.isEmpty)
        precondition(result.contains(target))
        precondition(result.contains(source))

        let beginner = DictionaryService().beginnerExplanation(
            for: target,
            sourceWord: source
        )
        precondition(!beginner.isEmpty)
        precondition(beginner.count <= 151)
        precondition(beginner.contains(target))

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

        let expanded = DictionaryService().adaptiveExpandedEnglish(
            for: "natural resources",
            sourceWord: "naturressourcer"
        )
        precondition(expanded.contains("natural resources"))
        precondition(!expanded.contains("…"))
        precondition(!expanded.contains("|"))
        precondition(expanded.split(separator: " ").count <= 38)
        print("Dictionary and beginner gloss checks passed")
    }
}
