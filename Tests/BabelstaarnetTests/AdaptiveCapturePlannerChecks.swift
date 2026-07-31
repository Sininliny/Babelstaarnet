import CoreGraphics

@main
enum AdaptiveCapturePlannerChecks {
    static func main() {
        textScaleChangesTheCaptureArea()
        pointerVelocityLooksAhead()
        captureStaysInsideNegativeOriginDisplay()
        sourceRectUsesTopLeftDisplayCoordinates()
        emptyOCRRequestsOneBoundedExpansion()
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
}
