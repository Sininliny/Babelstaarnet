import CoreGraphics
@testable import BabelCore
@testable import BabelstaarnetKit

@main
enum AdaptiveCapturePlannerChecks {
    static func main() {
        textScaleChangesTheCaptureArea()
        pointerVelocityLooksAhead()
        captureStaysInsideNegativeOriginDisplay()
        sourceRectUsesTopLeftDisplayCoordinates()
        emptyOCRRequestsOneBoundedExpansion()
        aWordAgainstTheCropEdgeExpands()
        aWordWellInsideTheCropDoesNot()
        aPageOfWordsIsNeverExpanded()
        textHeightFollowsTheMedianWord()
        print("Adaptive capture planner checks passed")
    }

    private static func textScaleChangesTheCaptureArea() {
        let screen = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let cursor = CGPoint(x: 960, y: 540)
        let small = AdaptiveCapturePlanner.captureFrame(
            around: cursor,
            on: screen,
            estimatedTextHeight: 9,
            velocity: .zero
        )
        let large = AdaptiveCapturePlanner.captureFrame(
            around: cursor,
            on: screen,
            estimatedTextHeight: 64,
            velocity: .zero
        )
        precondition(small.width >= 620)
        precondition(small.height >= 250)
        precondition(large.width > small.width)
        precondition(large.height > small.height)
        precondition(screen.contains(large))
    }

    private static func pointerVelocityLooksAhead() {
        let screen = CGRect(x: 0, y: 0, width: 2_000, height: 1_200)
        let cursor = CGPoint(x: 700, y: 600)
        let still = AdaptiveCapturePlanner.captureFrame(
            around: cursor,
            on: screen,
            estimatedTextHeight: 20,
            velocity: .zero
        )
        let moving = AdaptiveCapturePlanner.captureFrame(
            around: cursor,
            on: screen,
            estimatedTextHeight: 20,
            velocity: CursorVelocity(dx: 1_400, dy: 0)
        )
        precondition(moving.midX > still.midX)
        precondition(moving.width > still.width)
    }

    private static func captureStaysInsideNegativeOriginDisplay() {
        let screen = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let frame = AdaptiveCapturePlanner.captureFrame(
            around: CGPoint(x: -1_900, y: 1_060),
            on: screen,
            estimatedTextHeight: 88,
            velocity: CursorVelocity(dx: -900, dy: 600)
        )
        precondition(screen.contains(frame))
    }

    private static func sourceRectUsesTopLeftDisplayCoordinates() {
        let screen = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let capture = CGRect(x: -1_700, y: 180, width: 700, height: 300)
        let source = AdaptiveCapturePlanner.sourceRect(
            for: capture,
            on: screen
        )
        precondition(source == CGRect(x: 220, y: 600, width: 700, height: 300))
    }

    private static func emptyOCRRequestsOneBoundedExpansion() {
        precondition(
            AdaptiveCapturePlanner.shouldExpand(
                regions: [],
                captureFrame: CGRect(x: 0, y: 0, width: 700, height: 300)
            )
        )
    }

    /// A word touching the edge of the crop is a word the crop probably cut in
    /// half, which is the whole reason the expansion exists.
    private static func aWordAgainstTheCropEdgeExpands() {
        precondition(
            AdaptiveCapturePlanner.shouldExpand(
                regions: [region(words: [word(x: 10, y: 140)])],
                captureFrame: crop
            )
        )
        precondition(
            AdaptiveCapturePlanner.shouldExpand(
                regions: [
                    region(words: [word(x: 300, y: 140)]),
                    region(words: [word(x: 650, y: 140)])
                ],
                captureFrame: crop
            )
        )
    }

    private static func aWordWellInsideTheCropDoesNot() {
        precondition(
            !AdaptiveCapturePlanner.shouldExpand(
                regions: [region(words: [word(x: 300, y: 140)])],
                captureFrame: crop
            )
        )
    }

    /// Three words is already a reading, edges or not. The page behind a
    /// resting pointer arrives here with hundreds of them.
    private static func aPageOfWordsIsNeverExpanded() {
        let edgeHugging = (0..<40).map {
            region(words: [word(x: 4, y: CGFloat(8 + $0 * 6))])
        }
        precondition(
            !AdaptiveCapturePlanner.shouldExpand(
                regions: edgeHugging,
                captureFrame: crop
            )
        )
    }

    /// The median of the words actually read, with implausible boxes left out
    /// and the previous estimate still carrying most of the weight.
    private static func textHeightFollowsTheMedianWord() {
        let regions = [
            region(
                words: [
                    word(x: 100, y: 100, height: 2),
                    word(x: 200, y: 100, height: 20),
                    word(x: 300, y: 100, height: 22),
                    word(x: 400, y: 100, height: 24),
                    word(x: 500, y: 100, height: 900)
                ]
            )
        ]
        precondition(
            AdaptiveCapturePlanner.estimatedTextHeight(
                from: regions,
                previous: nil
            ) == 22
        )
        precondition(
            AdaptiveCapturePlanner.estimatedTextHeight(
                from: [region(words: [])],
                previous: 17
            ) == 17
        )
        let blended = AdaptiveCapturePlanner.estimatedTextHeight(
            from: regions,
            previous: 12
        )
        precondition(blended == 12 * 0.65 + 22 * 0.35)
    }

    private static let crop = CGRect(x: 0, y: 0, width: 700, height: 300)

    private static func word(
        x: CGFloat,
        y: CGFloat,
        height: CGFloat = 22
    ) -> WordRegion {
        WordRegion(
            sourceText: "ord",
            frame: CGRect(x: x, y: y, width: 40, height: height),
            screenFrame: crop,
            displayID: 1
        )
    }

    private static func region(words: [WordRegion]) -> TextRegion {
        TextRegion(
            sourceText: words.map(\.sourceText).joined(separator: " "),
            frame: words.dropFirst().reduce(words.first?.frame ?? .zero) {
                $0.union($1.frame)
            },
            screenFrame: crop,
            displayID: 1,
            words: words
        )
    }
}
