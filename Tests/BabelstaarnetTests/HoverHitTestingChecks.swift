import CoreGraphics

@main
enum HoverHitTestingChecks {
    static func main() {
        expandedEntryAreaCatchesOCRBoundaryMismatch()
        retentionAreaPreventsEdgeJitter()
        enteringANeighborSwitchesImmediately()
        refreshedGeometryKeepsTheSameTarget()
        refreshedRegionsKeepTheirIdentifiers()
        print("Hover hit-testing checks passed")
    }

    private static func expandedEntryAreaCatchesOCRBoundaryMismatch() {
        let word = makeWord("dansk", x: 100)
        let result = HoverHitTesting.word(
            at: CGPoint(x: 97, y: 112),
            in: [makeRegion(words: [word])],
            retaining: nil
        )
        precondition(result?.id == word.id)
    }

    private static func retentionAreaPreventsEdgeJitter() {
        let word = makeWord("dansk", x: 100)
        let result = HoverHitTesting.word(
            at: CGPoint(x: 92, y: 112),
            in: [makeRegion(words: [word])],
            retaining: word
        )
        precondition(result?.id == word.id)
    }

    private static func enteringANeighborSwitchesImmediately() {
        let first = makeWord("dansk", x: 100)
        let second = makeWord("tekst", x: 138)
        let result = HoverHitTesting.word(
            at: CGPoint(x: 143, y: 112),
            in: [makeRegion(words: [first, second])],
            retaining: first
        )
        precondition(result?.id == second.id)
    }

    private static func refreshedGeometryKeepsTheSameTarget() {
        let original = makeWord("markøren", x: 260)
        let refreshed = makeWord("markøren", x: 263)
        precondition(
            HoverHitTesting.representsSameTarget(original, refreshed)
        )
        precondition(
            HoverHitTesting.replacement(
                for: original,
                in: [refreshed]
            )?.id == refreshed.id
        )
    }

    private static func refreshedRegionsKeepTheirIdentifiers() {
        let original = makeWord("markøren", x: 260)
        let refreshed = makeWord("markøren", x: 263)
        let stabilized = HoverHitTesting.stabilizeIdentifiers(
            in: [makeRegion(words: [refreshed])],
            against: [makeRegion(words: [original])]
        )
        precondition(stabilized[0].words[0].id == original.id)
    }

    private static func makeWord(
        _ text: String,
        x: CGFloat
    ) -> WordRegion {
        WordRegion(
            sourceText: text,
            frame: CGRect(x: x, y: 100, width: 34, height: 22),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            displayID: 1
        )
    }

    private static func makeRegion(
        words: [WordRegion]
    ) -> TextRegion {
        TextRegion(
            sourceText: words.map(\.sourceText).joined(separator: " "),
            frame: words.dropFirst().reduce(words[0].frame) {
                $0.union($1.frame)
            },
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            displayID: 1,
            words: words
        )
    }
}
