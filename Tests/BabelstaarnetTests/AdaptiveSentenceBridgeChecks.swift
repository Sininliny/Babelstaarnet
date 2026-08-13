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
            unknown.text == "Hun hesitated, før hun svarede."
        )
        precondition(unknown.englishTokenIndexes == [1])

        let learning = service.bridge(
            danishSentence: sentence,
            englishByDanishWord: ["tøvede": "hesitated"],
            focusWord: "tøvede",
            stateForWord: { $0 == "tøvede" ? .learning : .known }
        )
        precondition(
            learning.text == "Hun hesitated, før hun svarede."
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

        // Structural words use a profile prior, never an absolute exclusion —
        // and pointing at one is a question about it, so the answer comes
        // whatever class the word belongs to. Only the rest of the line
        // withholds them, where an anchor would go to a word nobody asked
        // about.
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
        // The English inherits the capital of the Danish it stands in for.
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
        precondition(
            repeated.text == "Unknown ukendt second tredje."
        )
        precondition(repeated.englishTokenIndexes.count == 2)

        let repeatedFocus = service.bridge(
            danishSentence: "Ukendt ukendt.",
            englishByDanishWord: ["ukendt": "unknown"],
            focusWord: "ukendt",
            focusOccurrence: 1,
            stateForWord: { _ in .unknown }
        )
        precondition(repeatedFocus.text == "Ukendt unknown.")
        precondition(repeatedFocus.englishTokenIndexes == [1])

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
        precondition(priority.text == "Lært new third.")
        precondition(priority.englishTokenIndexes == [1, 2])

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
        precondition(usableOnly.text == "Uændret new.")
        precondition(usableOnly.englishTokenIndexes == [1])

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
            manyUnknown.text
                == "One two three four epsilon zeta eta eight.",
            manyUnknown.text
        )
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
        precondition(
            concise.text.hasPrefix("The very long translated"),
            concise.text
        )
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

        // The reported line. Two of three anchors went to "er" and "en", and
        // "er" — Danish for "is" — came back from word-at-a-time translation
        // as "no". Only "betingelse" is worth an anchor here.
        let functionWords = service.bridge(
            danishSentence: "Det er en betingelse for, at CPR-kontoret kan tildele.",
            englishByDanishWord: [
                "det": "that",
                "er": "no",
                "en": "a",
                "betingelse": "condition",
                "for": "for",
                "at": "that",
                "kan": "can",
                "tildele": "allocate"
            ],
            focusWord: "betingelse",
            stateForWord: { _ in .unknown }
        )
        precondition(
            functionWords.text
                == "Det er en condition for, at CPR-kontoret kan allocate.",
            functionWords.text
        )
        // The focus word is exempt, so hovering "er" still answers.
        let focusedFunctionWord = service.bridge(
            danishSentence: "Det er en betingelse.",
            englishByDanishWord: ["er": "is", "betingelse": "condition"],
            focusWord: "er",
            stateForWord: { _ in .unknown }
        )
        precondition(
            focusedFunctionWord.text == "Det is en condition.",
            "Pointing at a function word must still answer: "
                + focusedFunctionWord.text
        )

        for wasted in ["no", "that", "can"] {
            precondition(
                !functionWords.text.contains(wasted),
                "A function word was replaced: \(functionWords.text)"
            )
        }

        // Asking for all English is a request for the translation itself, so
        // the same line answers in full.
        let everyWord = service.bridge(
            danishSentence: "Det er en betingelse.",
            englishByDanishWord: [
                "det": "that",
                "er": "is",
                "en": "a",
                "betingelse": "condition"
            ],
            focusWord: "betingelse",
            stateForWord: { _ in .unknown },
            replacementLimit: 10,
            glossesEveryWord: true
        )
        precondition(
            everyWord.text == "That is a condition.",
            "All English skipped function words: \(everyWord.text)"
        )

        // A content word must never be mistaken for a function word, however
        // short or common it looks.
        for content in ["hus", "barn", "tildele", "betingelse", "personnummer"] {
            precondition(
                !DanishFunctionWords.contains(content),
                "\(content) is not a function word"
            )
        }
        for function in ["er", "en", "at", "og", "på", "som", "kan", "der"] {
            precondition(DanishFunctionWords.contains(function))
        }

        // The English takes the Danish word's case, since a word translated
        // on its own always comes back as though it opened a sentence.
        precondition(
            AdaptiveSentenceBridgeService.matchingCase(
                of: "Allocation",
                to: "tildele"
            ) == "allocation"
        )
        precondition(
            AdaptiveSentenceBridgeService.matchingCase(
                of: "condition",
                to: "Betingelsen"
            ) == "Condition"
        )
        precondition(
            AdaptiveSentenceBridgeService.matchingCase(
                of: "Copenhagen",
                to: "København"
            ) == "Copenhagen"
        )
        precondition(
            AdaptiveSentenceBridgeService.matchingCase(
                of: "condition",
                to: "betingelse"
            ) == "condition"
        )

        print("Adaptive sentence bridge checks passed")
    }
}
