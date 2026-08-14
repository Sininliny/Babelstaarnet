import Foundation
@testable import BabelstaarnetKit

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
        precondition(
            service.needsRetry(source: "for", translation: "no")
        )
        precondition(
            service.bestTranslation(
                source: "for",
                primary: "no",
                lowercaseRetry: "no"
            ) == "for"
        )
        precondition(
            service.bestTranslation(source: "for", primary: "too") == "too"
        )

        // Closed-class words are answered from the table rather than by the
        // translator. Once English stands in place of the Danish rather than
        // beside it, a wrong answer is the only thing the reader is left with,
        // and "er" asked on its own comes back as "no".
        precondition(service.bestTranslation(source: "er", primary: "no") == "is")
        precondition(service.bestTranslation(source: "på", primary: "in") == "on")
        precondition(service.bestTranslation(source: "må", primary: "must") == "may")
        precondition(
            service.bestTranslation(source: "ikke", primary: "not") == "not"
        )
        // A content word is still the translator's to answer.
        precondition(
            service.bestTranslation(
                source: "betingelse",
                primary: "condition"
            ) == "condition"
        )
        precondition(
            service.bestTranslation(
                source: "refleksionsperioden",
                primary: "the period of reflection"
            ) == "the period of reflection"
        )

        print("Translation retry and compound fallback checks passed")
    }
}
