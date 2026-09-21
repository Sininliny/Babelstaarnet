import Foundation
@testable import BabelTranslate
@testable import LanguageDanish

/// Runs the contextual glosser on words whose meaning the sentence decides.
///
/// Asserts only answers a working model cannot get wrong: the three words
/// word-at-a-time translation gets wrong, in sentences that leave one reading.
/// Decoding is greedy and the model revision is pinned, so a failure here is a
/// change in the model, the prompts, or the parsing, not chance.
///
/// Usage: ContextualGlossServiceCheck [python model-directory]
@main
enum ContextualGlossServiceCheck {
    static func main() async throws {
        let arguments = CommandLine.arguments
        let service = arguments.count == 3
            ? ContextualGlossService(
                language: .danish,
                pythonPath: arguments[1],
                modelDirectory: URL(fileURLWithPath: arguments[2])
            )
            : ContextualGlossService(language: .danish)
        guard service.isInstalled else {
            print("Contextual glosses are not installed; skipped")
            return
        }

        let loadStartedAt = CFAbsoluteTimeGetCurrent()
        let ready = await service.isReady()
        precondition(ready, "The contextual glosser failed to start")
        let loaded = CFAbsoluteTimeGetCurrent() - loadStartedAt

        let cases: [(String, String, String)] = [
            ("Han får en ny bil i morgen.", "får", "get"),
            ("Der går tre får på marken.", "får", "sheep"),
            ("Kan du lide æbler?", "lide", "like")
        ]
        let policy = ContextualGlossPolicy(languages: .danishToEnglish)
        var slowest = 0.0
        for (sentence, focus, expected) in cases {
            let words = sentence
                .split { !$0.isLetter }
                .map(String.init)
            let startedAt = CFAbsoluteTimeGetCurrent()
            let answer = try await service.gloss(
                sentence: sentence,
                words: words,
                focus: focus
            )
            slowest = max(slowest, CFAbsoluteTimeGetCurrent() - startedAt)

            precondition(answer.glosses.count == words.count)
            let index = words.firstIndex(of: focus)!
            let meaning = policy.meaning(
                sentenceGloss: answer.glosses[index],
                focus: answer.focus
            ) ?? ""
            precondition(
                meaning.localizedCaseInsensitiveContains(expected),
                "“\(focus)” in “\(sentence)” was glossed “\(meaning)”"
            )
            let explanation = policy.explanation(
                for: answer.focus,
                sentenceGloss: answer.glosses[index]
            ) ?? "(set aside)"
            print("\(focus) → \(meaning) | \(explanation)")
        }
        precondition(
            slowest < 3,
            "A warm contextual gloss exceeded three seconds: \(slowest)"
        )

        await service.shutdown()
        print(
            "Contextual gloss check passed: loaded in "
                + loaded.formatted(.number.precision(.fractionLength(1)))
                + " s, slowest sentence "
                + slowest.formatted(.number.precision(.fractionLength(2)))
                + " s"
        )
    }
}
