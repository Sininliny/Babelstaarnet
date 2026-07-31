import Foundation

@main
enum ArgosServiceCheck {
    static func main() async throws {
        let service = ArgosTranslationService()
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

        let wordWiseService = ArgosTranslationService()
        let wordWiseReady = await wordWiseService.isWordWiseReady()
        precondition(
            wordWiseReady,
            "Easy Danish model or local WordNet data is not installed"
        )
        let explanations = try await wordWiseService
            .explainEnglishWordsInDanish([
                "dictionary",
                "learn",
                "course"
            ])
        precondition(explanations.count == 3)
        precondition(explanations.allSatisfy { !$0.isEmpty })
        precondition(
            explanations.allSatisfy {
                !$0.localizedCaseInsensitiveContains(
                    "a word or expression with the meaning"
                )
            }
        )
        print(
            "Easy Danish WordNet + Argos check passed: "
                + explanations.joined(separator: " · ")
        )
    }
}
