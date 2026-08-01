import Foundation

@main
enum TranslationQualityChecks {
    static func main() {
        let service = TranslationQualityService()
        precondition(
            service.needsRetry(
                source: "Webarkitektur",
                translation: "Webarkitektur"
            )
        )
        precondition(
            service.bestTranslation(
                source: "Webarkitektur",
                primary: "Webarkitektur"
            ) == "web architecture"
        )
        precondition(
            service.bestTranslation(
                source: "Computernetværk",
                primary: "Computernetværk"
            ) == "computer network"
        )
        precondition(
            service.bestTranslation(
                source: "Avanceret",
                primary: "Avanceret",
                lowercaseRetry: "Advanced"
            ) == "Advanced"
        )
        precondition(
            !service.needsRetry(
                source: "morgen",
                translation: "morning"
            )
        )
        print("Translation retry and compound fallback checks passed")
    }
}
