import Foundation

@main
enum AdaptiveWordBridgeChecks {
    static func main() {
        let danishService = BeginnerDanishService()
        let bridgeService = AdaptiveSentenceBridgeService()
        precondition(danishService.clean(explanation: "Betyder.").isEmpty)
        precondition(danishService.clean(explanation: "Det betyder.").isEmpty)
        precondition(
            danishService.clean(explanation: "Betyder at lære noget")
                == "Betyder at lære noget."
        )
        guard let explanation = danishService.localExplanation(for: "lære") else {
            preconditionFailure("Expected a local Danish word explanation")
        }

        let bridge = bridgeService.bridge(
            danishSentence: explanation,
            englishByDanishWord: [
                "viden": "knowledge",
                "færdighed": "skill"
            ],
            focusWord: "",
            stateForWord: { word in
                word == "viden" ? .known : .unknown
            }
        )
        precondition(bridge.text.contains("viden"))
        precondition(!bridge.text.contains("knowledge"))
        precondition(bridge.text.contains("skill"))
        precondition(bridge.text.contains("færdighed"))
        precondition(
            bridge.englishTokenIndexes.allSatisfy {
                bridge.text.split(separator: " ").indices.contains($0)
            }
        )

        let needed = bridgeService.wordsNeedingEnglish(
            in: explanation,
            stateForWord: { $0 == "viden" ? .known : .unknown }
        )
        precondition(!needed.contains("viden"))
        precondition(needed.contains("færdighed"))

        guard let housingExplanation = danishService.localExplanation(
            for: "studieboliger"
        ) else {
            preconditionFailure(
                "Expected a compound-aware Danish housing explanation"
            )
        }
        let housingBridge = bridgeService.bridge(
            danishSentence: housingExplanation,
            englishByDanishWord: [
                "boliger": "housing",
                "lavet": "made",
                "studerende": "students"
            ],
            focusWord: "",
            stateForWord: { _ in .unknown }
        )
        precondition(
            housingBridge.text
                == "Boliger housing, der er lavet made til studerende students."
        )
        precondition(housingBridge.englishTokenIndexes == [1, 5, 8])

        print("Adaptive word bridge checks passed")
    }
}
