import CoreGraphics
@testable import BabelCore
@testable import BabelstaarnetKit

@main
enum HoverHitTestingChecks {
    static func main() {
        expandedEntryAreaCatchesOCRBoundaryMismatch()
        retentionAreaPreventsEdgeJitter()
        enteringANeighborSwitchesImmediately()
        refreshedGeometryKeepsTheSameTarget()
        refreshedRegionsKeepTheirIdentifiers()
        eachPreviousIdentifierIsClaimedOnce()
        aRepeatedWordTakesTheNearestIdentifier()
        aWordThatMovedTooFarKeepsAFreshIdentifier()
        anUnchangedIdentifierSurvivesARenamedWord()
        identifiersStayUniqueAcrossAWholePage()
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

    /// A previous word answers for one word only. Two copies of the same word
    /// must not both inherit it, or the scan would carry two words with one
    /// identifier and the translation map keyed on it would lose one of them.
    private static func eachPreviousIdentifierIsClaimedOnce() {
        let original = makeWord("og", x: 100)
        let first = makeWord("og", x: 101)
        let second = makeWord("og", x: 118)
        let stabilized = HoverHitTesting.stabilizeIdentifiers(
            in: [makeRegion(words: [first, second])],
            against: [makeRegion(words: [original])]
        )
        let identifiers = stabilized.flatMap(\.words).map(\.id)
        precondition(identifiers[0] == original.id)
        precondition(identifiers[1] != original.id)
        precondition(Set(identifiers).count == identifiers.count)
    }

    /// With the word repeated in the previous scan too, each new copy takes the
    /// one it is nearest to rather than whichever came first.
    private static func aRepeatedWordTakesTheNearestIdentifier() {
        let near = makeWord("i", x: 100)
        let far = makeWord("i", x: 400)
        let refreshedFar = makeWord("i", x: 402)
        let refreshedNear = makeWord("i", x: 102)
        let stabilized = HoverHitTesting.stabilizeIdentifiers(
            in: [makeRegion(words: [refreshedFar, refreshedNear])],
            against: [makeRegion(words: [near, far])]
        )
        let identifiers = stabilized.flatMap(\.words).map(\.id)
        precondition(identifiers[0] == far.id)
        precondition(identifiers[1] == near.id)
    }

    /// Past the tolerance the same spelling is a different word on the page,
    /// so it starts as one rather than inheriting an identifier.
    private static func aWordThatMovedTooFarKeepsAFreshIdentifier() {
        let original = makeWord("undervisning", x: 100)
        let moved = makeWord("undervisning", x: 400)
        let stabilized = HoverHitTesting.stabilizeIdentifiers(
            in: [makeRegion(words: [moved])],
            against: [makeRegion(words: [original])]
        )
        precondition(stabilized[0].words[0].id == moved.id)
    }

    /// An identifier that is already the same settles it, whatever the text
    /// around it now reads as.
    private static func anUnchangedIdentifierSurvivesARenamedWord() {
        let original = makeWord("laering", x: 100)
        let reread = WordRegion(
            id: original.id,
            sourceText: "læring",
            frame: original.frame,
            screenFrame: original.screenFrame,
            displayID: original.displayID
        )
        let stabilized = HoverHitTesting.stabilizeIdentifiers(
            in: [makeRegion(words: [reread])],
            against: [makeRegion(words: [original])]
        )
        precondition(stabilized[0].words[0].id == original.id)
        precondition(stabilized[0].words[0].sourceText == "læring")
    }

    /// The whole-page case, which is what a pointer resting on blank space
    /// produces: every identifier still has to come out distinct.
    private static func identifiersStayUniqueAcrossAWholePage() {
        let previous = makePage(offset: 0)
        let current = makePage(offset: 2)
        let stabilized = HoverHitTesting.stabilizeIdentifiers(
            in: current,
            against: previous
        )
        let words = stabilized.flatMap(\.words)
        precondition(Set(words.map(\.id)).count == words.count)
        // Same page, barely moved: every word should have kept its identifier.
        let carried = Set(previous.flatMap(\.words).map(\.id))
        precondition(words.allSatisfy { carried.contains($0.id) })
        precondition(
            zip(words, current.flatMap(\.words))
                .allSatisfy { $0.sourceText == $1.sourceText }
        )
    }

    private static func makePage(offset: CGFloat) -> [TextRegion] {
        (0..<12).map { line in
            makeRegion(
                words: (0..<10).map { index in
                    WordRegion(
                        sourceText: "ord\(index)",
                        frame: CGRect(
                            x: CGFloat(40 + index * 60) + offset,
                            y: CGFloat(700 - line * 30),
                            width: 34,
                            height: 22
                        ),
                        screenFrame: CGRect(
                            x: 0,
                            y: 0,
                            width: 1_440,
                            height: 900
                        ),
                        displayID: 1
                    )
                }
            )
        }
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
