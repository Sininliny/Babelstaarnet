import CoreGraphics

@main
enum BubbleInteractionChecks {
    static func main() {
        precondition(
            BubbleInteractionPolicy.pointerIsStationary(
                CGPoint(x: 101, y: 99),
                since: CGPoint(x: 100, y: 100)
            )
        )
        precondition(
            !BubbleInteractionPolicy.pointerIsStationary(
                CGPoint(x: 104, y: 100),
                since: CGPoint(x: 100, y: 100)
            )
        )
        precondition(
            BubbleInteractionPolicy.shouldKeepLearningSnapshot(
                pointer: CGPoint(x: 102, y: 101),
                anchor: CGPoint(x: 100, y: 100),
                interactionIsHeld: false
            )
        )
        precondition(
            !BubbleInteractionPolicy.shouldKeepLearningSnapshot(
                pointer: CGPoint(x: 112, y: 100),
                anchor: CGPoint(x: 100, y: 100),
                interactionIsHeld: false
            )
        )
        precondition(
            BubbleInteractionPolicy.shouldKeepLearningSnapshot(
                pointer: CGPoint(x: 400, y: 400),
                anchor: CGPoint(x: 100, y: 100),
                interactionIsHeld: true
            )
        )
        precondition(
            BubbleInteractionPolicy.shouldPinAfterStationaryHover(
                point: CGPoint(x: 110, y: 110),
                anchor: CGPoint(x: 111, y: 109),
                elapsed: 0.75,
                sourceFrame: CGRect(x: 100, y: 100, width: 50, height: 20)
            )
        )
        precondition(
            !BubbleInteractionPolicy.shouldPinAfterStationaryHover(
                point: CGPoint(x: 110, y: 110),
                anchor: CGPoint(x: 111, y: 109),
                elapsed: 0.74,
                sourceFrame: CGRect(x: 100, y: 100, width: 50, height: 20)
            )
        )
        precondition(
            BubbleInteractionPolicy.shouldReleaseTemporaryHold(
                pointerMoved: true,
                idleDuration: 10
            )
        )
        precondition(
            BubbleInteractionPolicy.shouldReleaseTemporaryHold(
                pointerMoved: false,
                idleDuration: 0.05
            )
        )
        precondition(
            !BubbleInteractionPolicy.shouldReleaseTemporaryHold(
                pointerMoved: false,
                idleDuration: 2
            )
        )

        let bubble = CGRect(x: 80, y: 145, width: 320, height: 120)
        let resized = BubbleInteractionPolicy.preservedFrame(
            oldFrame: bubble,
            newSize: CGSize(width: 320, height: 170),
            screenFrame: CGRect(x: 0, y: 0, width: 900, height: 700)
        )
        precondition(resized.minX == bubble.minX)
        precondition(resized.maxY == bubble.maxY)
        precondition(resized.height == 170)

        print("Bubble stationary stability checks passed")
    }
}
