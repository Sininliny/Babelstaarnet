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

        // Reading past a word must never put a question in front of the
        // learner. Only a deliberate hold invites the feedback controls.
        precondition(
            !BridgeAttentionPolicy.showsFeedbackControls(
                bubbleIsHeld: false,
                hasSettledOnWord: false
            )
        )
        precondition(
            BridgeAttentionPolicy.showsFeedbackControls(
                bubbleIsHeld: true,
                hasSettledOnWord: false
            )
        )

        // The reported fault: the hold is released by any system input at all,
        // so a keystroke or a scroll while the pointer rested on a word made
        // the controls vanish and then return 0.75 s later, over and over.
        // Once settled, they hold through that.
        precondition(
            BridgeAttentionPolicy.showsFeedbackControls(
                bubbleIsHeld: false,
                hasSettledOnWord: true
            )
        )
        precondition(
            BridgeAttentionPolicy.showsFeedbackControls(
                bubbleIsHeld: true,
                hasSettledOnWord: true
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

        // A bubble sitting above the line it explains must grow upwards. The
        // old behaviour held the top edge, so every extra row expanded down
        // over the words the reader was looking at.
        let source = CGRect(x: 80, y: 100, width: 300, height: 20)
        let above = CGRect(x: 80, y: 129, width: 320, height: 90)
        precondition(
            BubbleInteractionPolicy.GrowthAnchor.growingAwayFrom(
                sourceFrame: source,
                bubbleFrame: above
            ) == .bottom
        )
        let grown = BubbleInteractionPolicy.preservedFrame(
            oldFrame: above,
            newSize: CGSize(width: 320, height: 140),
            screenFrame: CGRect(x: 0, y: 0, width: 900, height: 700),
            anchoring: .bottom
        )
        precondition(grown.minY == above.minY, "Bubble grew toward the text")
        precondition(grown.minY >= source.maxY, "Bubble overlaps the text")

        let below = CGRect(x: 80, y: 20, width: 320, height: 70)
        precondition(
            BubbleInteractionPolicy.GrowthAnchor.growingAwayFrom(
                sourceFrame: source,
                bubbleFrame: below
            ) == .top
        )

        print("Bubble stationary stability checks passed")
    }
}
