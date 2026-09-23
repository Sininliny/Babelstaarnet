import CoreGraphics
import Foundation
@testable import BabelCore
@testable import BabelTranslate
@testable import BabelstaarnetKit
@testable import LanguageDanish

/// The scheduling the reader actually feels: what is asked for a sentence,
/// what is asked again for the next word in it, and what happens to a question
/// the pointer has already moved on from.
///
/// Runs against the installed model, and reports itself skipped without one.
@main
enum ContextualGlossCoordinatorCheck {
    private static let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    @MainActor
    static func main() async throws {
        let service = ContextualGlossService(language: .danish)
        guard service.isInstalled else {
            print("Contextual glosses are not installed; skipped")
            return
        }
        var failure: String?
        let coordinator = ContextualGlossCoordinator(
            service: service,
            languages: .danishToEnglish,
            onFailure: { failure = $0.localizedDescription }
        )

        let page = [line("Han får en ny bil i morgen.", top: 600)]
        let assembly = SentenceAssemblyPolicy(language: .danish)
        func request(_ word: String) -> ContextualGlossRequest {
            ContextualGlossRequest(
                containing: self.word(word, in: page[0]),
                in: page[0],
                among: page,
                language: .danish,
                assembly: assembly
            )!
        }

        let gets = request("får")
        precondition(
            coordinator.cachedAnswer(for: gets) == nil,
            "Nothing has been asked yet"
        )

        let firstWord = try await measure {
            await answer(coordinator, gets)
        }
        precondition(failure == nil, failure ?? "")
        guard let sentenceAnswer = coordinator.cachedAnswer(for: gets) else {
            preconditionFailure("The sentence was not answered")
        }
        precondition(
            sentenceAnswer.glossesByWord["får"]?
                .localizedCaseInsensitiveContains("get") == true,
            "“får” was glossed \(sentenceAnswer.glossesByWord["får"] ?? "nothing")"
        )
        // Every word of the sentence comes back from the one request, so the
        // rest of the line is already answered.
        precondition(
            sentenceAnswer.glossesByWord.count >= 6,
            "Only \(sentenceAnswer.glossesByWord.count) words were glossed"
        )
        precondition(
            sentenceAnswer.explanation?.isEmpty == false,
            "No explanation survived the policy"
        )

        // The next word in the same sentence keeps the sentence's answers and
        // asks only for its own explanation, which is the shorter question.
        let car = request("bil")
        precondition(coordinator.cachedAnswer(for: car) == nil)
        let nextWord = try await measure {
            await answer(coordinator, car)
        }
        guard let carAnswer = coordinator.cachedAnswer(for: car) else {
            preconditionFailure("The second word was not answered")
        }
        precondition(
            carAnswer.glossesByWord["får"] == sentenceAnswer.glossesByWord["får"],
            "The sentence was glossed again"
        )
        precondition(
            nextWord < firstWord,
            "Asking about a word in a sentence already read cost as much as"
                + " the sentence: \(nextWord) against \(firstWord)"
        )

        // A pointer moving along the line leaves questions behind it. Only one
        // is ever in flight, and the last one asked is the one answered.
        var answered: [String] = []
        coordinator.ask(request("ny")) { answered.append("ny") }
        coordinator.ask(request("morgen")) { answered.append("morgen") }
        coordinator.ask(request("Han")) { answered.append("Han") }
        try await waitUntil { answered.contains("Han") }
        precondition(
            !answered.contains("morgen"),
            "A question the pointer had moved on from was still answered"
        )
        precondition(failure == nil, failure ?? "")

        await service.shutdown()
        print(
            "Contextual gloss coordinator check passed: sentence in "
                + firstWord.formatted(.number.precision(.fractionLength(2)))
                + " s, next word in "
                + nextWord.formatted(.number.precision(.fractionLength(2)))
                + " s"
        )
    }

    @MainActor
    private static func answer(
        _ coordinator: ContextualGlossCoordinator,
        _ request: ContextualGlossRequest
    ) async {
        var done = false
        coordinator.ask(request) { done = true }
        try? await waitUntil { done }
    }

    @MainActor
    private static func waitUntil(
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !condition() {
            precondition(
                Date() < deadline,
                "The glosser did not answer within thirty seconds"
            )
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func measure(
        _ work: () async -> Void
    ) async throws -> Double {
        let startedAt = CFAbsoluteTimeGetCurrent()
        await work()
        return CFAbsoluteTimeGetCurrent() - startedAt
    }

    private static func line(
        _ text: String,
        top: CGFloat,
        left: CGFloat = 100,
        height: CGFloat = 24
    ) -> TextRegion {
        var x = left
        var words: [WordRegion] = []
        for token in text.split(whereSeparator: \Character.isWhitespace) {
            let width = CGFloat(token.count) * 9
            words.append(
                WordRegion(
                    sourceText: String(token).trimmingCharacters(
                        in: .punctuationCharacters
                    ),
                    frame: CGRect(x: x, y: top, width: width, height: height),
                    screenFrame: screen,
                    displayID: 1
                )
            )
            x += width + 6
        }
        return TextRegion(
            sourceText: text,
            frame: CGRect(x: left, y: top, width: x - left - 6, height: height),
            screenFrame: screen,
            displayID: 1,
            words: words
        )
    }

    private static func word(
        _ text: String,
        in region: TextRegion
    ) -> WordRegion {
        guard let match = region.words.first(where: {
            $0.sourceText.lowercased() == text.lowercased()
        }) else {
            preconditionFailure("\(text) is not on this line")
        }
        return match
    }
}
