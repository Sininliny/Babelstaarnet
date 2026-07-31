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
        print("Dictionary and beginner gloss checks passed")
    }
}
