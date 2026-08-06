import Foundation

@main
enum AdaptiveSentenceBridgeChecks {
    static func main() {
        precondition(LanguageTransferState.forKnowledgeLevel(0) == .unknown)
        precondition(LanguageTransferState.forKnowledgeLevel(1) == .learning)
        precondition(LanguageTransferState.forKnowledgeLevel(3) == .testing)
        precondition(LanguageTransferState.forKnowledgeLevel(4) == .known)
        precondition(LanguageTransferState.forKnowledgeLevel(5) == .known)
        precondition(
            AdaptiveMeaningCoveragePolicy.englishAnchorLimit(
                totalWordCount: 8,
                wordsNeedingSupport: 0
            ) == 0
        )
        precondition(
            AdaptiveMeaningCoveragePolicy.englishAnchorLimit(
                totalWordCount: 8,
                wordsNeedingSupport: 2
            ) == 2
        )
        precondition(
            AdaptiveMeaningCoveragePolicy.englishAnchorLimit(
                totalWordCount: 10,
                wordsNeedingSupport: 4
            ) == 3
        )
        precondition(
            AdaptiveMeaningCoveragePolicy.englishAnchorLimit(
                totalWordCount: 8,
                wordsNeedingSupport: 8
            ) == 5
        )

        let service = AdaptiveSentenceBridgeService()
        let sentence = "Hun tøvede, før hun svarede."

        let unknown = service.bridge(
            danishSentence: sentence,
            englishByDanishWord: ["tøvede": "hesitated"],
            focusWord: "tøvede",
            stateForWord: { $0 == "tøvede" ? .unknown : .known }
        )
        precondition(
            unknown.text == "Hun tøvede hesitated, før hun svarede."
        )
        precondition(unknown.englishTokenIndexes == [2])

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
        precondition(unknownGrammar.text == "Jeg er i in huset.")
        precondition(unknownGrammar.englishTokenIndexes == [3])

        let capitalized = service.bridge(
            danishSentence: "Tøvede hun?",
            englishByDanishWord: ["tøvede": "hesitated"],
            focusWord: "Tøvede",
            stateForWord: { _ in .unknown }
        )
        precondition(capitalized.text == "Tøvede hesitated hun?")
        precondition(capitalized.englishTokenIndexes == [1])

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
        precondition(
            repeated.text
                == "Ukendt unknown ukendt andet second tredje."
        )
        precondition(repeated.englishTokenIndexes.count == 2)

        let repeatedFocus = service.bridge(
            danishSentence: "Ukendt ukendt.",
            englishByDanishWord: ["ukendt": "unknown"],
            focusWord: "ukendt",
            focusOccurrence: 1,
            stateForWord: { _ in .unknown }
        )
        precondition(repeatedFocus.text == "Ukendt ukendt unknown.")
        precondition(repeatedFocus.englishTokenIndexes == [2])

        let priority = service.bridge(
            danishSentence: "Lært nyt tredje.",
            englishByDanishWord: [
                "lært": "learned",
                "nyt": "new",
                "tredje": "third"
            ],
            focusWord: "tredje",
            stateForWord: {
                $0 == "nyt" ? .unknown : .learning
            },
            replacementLimit: 2
        )
        precondition(priority.text == "Lært nyt new tredje third.")
        precondition(priority.englishTokenIndexes == [2, 4])

        let usableOnly = service.bridge(
            danishSentence: "Uændret nyt.",
            englishByDanishWord: [
                "uændret": "uændret",
                "nyt": "new"
            ],
            focusWord: "",
            stateForWord: { _ in .unknown },
            replacementLimit: 1
        )
        precondition(usableOnly.text == "Uændret nyt new.")
        precondition(usableOnly.englishTokenIndexes == [2])

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
        precondition(manyUnknown.text.contains("Alpha one"))
        precondition(manyUnknown.text.contains("beta two"))
        precondition(manyUnknown.text.contains("gamma three"))
        precondition(manyUnknown.text.contains("delta four"))
        precondition(manyUnknown.text.contains("theta eight"))
        precondition(!manyUnknown.text.contains("epsilon five"))
        precondition(manyUnknown.englishTokenIndexes.count == 5)

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
        precondition(
            focused.text.split(separator: " ").count
                - focused.englishTokenIndexes.count <= 10
        )

        let concise = service.bridge(
            danishSentence: "Begrebet virker.",
            englishByDanishWord: [
                "begrebet": "the very long translated meaning here"
            ],
            focusWord: "Begrebet",
            stateForWord: { _ in .unknown }
        )
        precondition(concise.text.hasPrefix("Begrebet the very long translated"))
        precondition(!concise.text.contains("meaning"))
        precondition(concise.englishTokenIndexes == [1, 2, 3, 4])

        let collision = service.bridge(
            danishSentence: "Et land blev kaldt land.",
            englishByDanishWord: ["kaldt": "called"],
            focusWord: "kaldt",
            stateForWord: { $0 == "kaldt" ? .unknown : .known }
        )
        precondition(collision.text == "Et land blev kaldt called land.")
        precondition(collision.englishTokenIndexes == [4])

        print("Adaptive sentence bridge checks passed")
    }
}
