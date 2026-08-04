import Foundation

@main
enum AdaptiveSentenceBridgeChecks {
    static func main() {
        precondition(LanguageTransferState.forKnowledgeLevel(0) == .unknown)
        precondition(LanguageTransferState.forKnowledgeLevel(1) == .learning)
        precondition(LanguageTransferState.forKnowledgeLevel(3) == .testing)
        precondition(LanguageTransferState.forKnowledgeLevel(4) == .known)
        precondition(LanguageTransferState.forKnowledgeLevel(5) == .known)

        let service = AdaptiveSentenceBridgeService()
        let sentence = "Hun tøvede, før hun svarede."

        let unknown = service.bridge(
            danishSentence: sentence,
            englishByDanishWord: ["tøvede": "hesitated"],
            focusWord: "tøvede",
            stateForWord: { $0 == "tøvede" ? .unknown : .known }
        )
        precondition(unknown.text == "Hun hesitated, før hun svarede.")
        precondition(unknown.englishTokenIndexes == [1])

        let learning = service.bridge(
            danishSentence: sentence,
            englishByDanishWord: ["tøvede": "hesitated"],
            focusWord: "tøvede",
            stateForWord: { $0 == "tøvede" ? .learning : .known }
        )
        precondition(
            learning.text == "Hun tøvede hesitated, før hun svarede."
        )

        let known = service.bridge(
            danishSentence: sentence,
            englishByDanishWord: ["tøvede": "hesitated"],
            focusWord: "tøvede",
            stateForWord: { _ in .known }
        )
        precondition(known.text == sentence)
        precondition(known.englishTokenIndexes.isEmpty)

        let testing = service.bridge(
            danishSentence: sentence,
            englishByDanishWord: ["tøvede": "hesitated"],
            focusWord: "tøvede",
            stateForWord: { $0 == "tøvede" ? .testing : .known }
        )
        precondition(testing.text == sentence)
        precondition(testing.englishTokenIndexes.isEmpty)

        // Structural words use a profile prior, never an absolute exclusion.
        let unknownGrammar = service.bridge(
            danishSentence: "Jeg er i huset.",
            englishByDanishWord: ["i": "in"],
            focusWord: "i",
            stateForWord: { $0 == "i" ? .unknown : .known }
        )
        precondition(unknownGrammar.text == "Jeg er in huset.")
        precondition(unknownGrammar.englishTokenIndexes == [2])

        let capitalized = service.bridge(
            danishSentence: "Tøvede hun?",
            englishByDanishWord: ["tøvede": "hesitated"],
            focusWord: "Tøvede",
            stateForWord: { _ in .unknown }
        )
        precondition(capitalized.text == "Hesitated hun?")
        precondition(capitalized.englishTokenIndexes == [0])

        let repeated = service.bridge(
            danishSentence: "Ukendt ukendt andet tredje.",
            englishByDanishWord: [
                "ukendt": "unknown",
                "andet": "second",
                "tredje": "third"
            ],
            focusWord: "andet",
            stateForWord: { _ in .unknown },
            replacementLimit: 2
        )
        precondition(repeated.text == "Unknown unknown second tredje.")

        let manyUnknown = service.bridge(
            danishSentence: "Alpha beta gamma delta epsilon zeta eta theta.",
            englishByDanishWord: [
                "alpha": "one",
                "beta": "two",
                "gamma": "three",
                "delta": "four",
                "epsilon": "five",
                "zeta": "six",
                "eta": "seven",
                "theta": "eight"
            ],
            focusWord: "theta",
            stateForWord: { _ in .unknown }
        )
        precondition(
            manyUnknown.text == "One two three four five six seven eight."
        )
        precondition(manyUnknown.englishTokenIndexes == Array(0..<8))

        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let longWords = (0..<30).map {
            "ord\(letters[$0 / 26])\(letters[$0 % 26])"
        }
        let longSentence = longWords.joined(separator: " ") + "."
        let focused = service.bridge(
            danishSentence: longSentence,
            englishByDanishWord: ["ordba": "focus"],
            focusWord: "ordba",
            stateForWord: { $0 == "ordba" ? .unknown : .known },
            wordLimit: 10
        )
        precondition(focused.text.contains("focus"))
        precondition(!focused.text.contains("ordaa "))
        precondition(focused.text.split(separator: " ").count <= 10)

        let concise = service.bridge(
            danishSentence: "Begrebet virker.",
            englishByDanishWord: [
                "begrebet": "the very long translated meaning here"
            ],
            focusWord: "Begrebet",
            stateForWord: { _ in .unknown }
        )
        precondition(concise.text.hasPrefix("The very long translated"))
        precondition(!concise.text.contains("meaning"))
        precondition(concise.englishTokenIndexes == [0, 1, 2, 3])

        let collision = service.bridge(
            danishSentence: "Et land blev kaldt land.",
            englishByDanishWord: ["kaldt": "called"],
            focusWord: "kaldt",
            stateForWord: { $0 == "kaldt" ? .unknown : .known }
        )
        precondition(collision.text == "Et land blev called land.")
        precondition(collision.englishTokenIndexes == [3])

        print("Adaptive sentence bridge checks passed")
    }
}
