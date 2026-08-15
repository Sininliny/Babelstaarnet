import Foundation
@testable import BabelTranslate
@testable import LanguageDanish

@main
enum ArgosServiceCheck {
    static func main() async throws {
        let service = ArgosTranslationService(languages: .danishToEnglish)
        let ready = await service.isReady()
        precondition(
            ready,
            "Persistent Argos worker failed to warm up"
        )

        let startedAt = CFAbsoluteTimeGetCurrent()
        let translations = try await service.translate([
            "Godmorgen",
            "hvordan",
            "ordbog"
        ])
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt

        precondition(translations.count == 3)
        precondition(
            translations[0].localizedCaseInsensitiveContains("morning")
        )
        precondition(
            translations[2].localizedCaseInsensitiveContains("dictionary")
        )
        precondition(
            elapsed < 1,
            "Warm local translation exceeded one second: \(elapsed)"
        )

        print(
            "Persistent Argos check passed in "
                + elapsed.formatted(
                    .number.precision(.fractionLength(3))
                )
                + " s"
        )

        let wordBridgeService = ArgosTranslationService(languages: .danishToEnglish)
        let wordBridgeReady = await wordBridgeService.isWordBridgeReady()
        precondition(
            wordBridgeReady,
            "Adaptive word-bridge resources are not installed"
        )
        let explanations = try await wordBridgeService
            .explainTargetWordsInSourceLanguage([
                "study accommodation",
                "learn"
        ])
        precondition(explanations.count == 2)
        precondition(explanations.allSatisfy { !$0.isEmpty })
        precondition(
            explanations.allSatisfy {
                $0.split(whereSeparator: \Character.isWhitespace).count >= 3
            },
            "Word bridge returned a direct translation instead of an explanation"
        )
        print(
            "Adaptive word-bridge runtime check passed: "
                + explanations.joined(separator: " | ")
        )
    }
}
