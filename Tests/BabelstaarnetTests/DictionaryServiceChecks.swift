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
        print("Dictionary fallback checks passed")
    }
}
