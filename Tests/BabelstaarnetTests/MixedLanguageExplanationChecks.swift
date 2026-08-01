import Foundation

@main
enum MixedLanguageExplanationChecks {
    static func main() {
        let service = MixedLanguageExplanationService()
        let danish = "Den første del af dagen, der varer fra solopgang til klokken ca. 9."
        let familiar = Set(["dagen", "varer"])
        let needed = service.wordsNeedingEnglish(
            in: danish,
            isFamiliar: { familiar.contains($0) }
        )
        precondition(needed.contains("første"))
        precondition(needed.contains("del"))
        precondition(needed.contains("solopgang"))
        precondition(!needed.contains("den"))
        precondition(!needed.contains("dagen"))
        precondition(needed.count <= 6)

        let mixed = service.mix(
            danishExplanation: danish,
            englishByDanishWord: [
                "første": "first",
                "del": "part",
                "solopgang": "sunrise",
                "klokken": "the clock"
            ],
            isFamiliar: { familiar.contains($0) }
        )
        precondition(
            mixed == "Den first part af dagen, der varer fra sunrise til the clock ca. 9."
        )
        precondition(!mixed.contains("…"))

        let learned = service.mix(
            danishExplanation: danish,
            englishByDanishWord: ["første": "first"],
            isFamiliar: { $0 == "første" }
        )
        precondition(learned.contains("første"))
        precondition(!learned.contains("first"))

        print("Mixed local explanation checks passed")
    }
}
