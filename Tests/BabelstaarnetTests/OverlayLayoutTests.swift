import CoreGraphics

@main
struct OverlayLayoutChecks {
    static func main() {
        translationBubbleNeverCoversSourceWhenThereIsRoomBelow()
        translationBubbleMovesAboveNearBottomEdge()
        hoverBubbleStaysInsideNegativeOriginDisplay()
        hoverBubbleFallsBackWhenDenseTextBlocksEveryPreferredPosition()
        print("Overlay layout checks passed")
    }

    static func translationBubbleNeverCoversSourceWhenThereIsRoomBelow() {
        let source = CGRect(x: 300, y: 400, width: 180, height: 24)
        let size = CGSize(width: 220, height: 42)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        guard let center = OverlayLayout.translationCenter(
            sourceFrame: source,
            estimatedSize: size,
            screenFrame: screen
        ) else {
            preconditionFailure("Expected a safe placement")
        }
        let bubble = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        precondition(!bubble.intersects(source))
        precondition(screen.contains(bubble))
    }

    static func translationBubbleMovesAboveNearBottomEdge() {
        let source = CGRect(x: 80, y: 4, width: 120, height: 20)
        let size = CGSize(width: 160, height: 40)
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)

        guard let center = OverlayLayout.translationCenter(
            sourceFrame: source,
            estimatedSize: size,
            screenFrame: screen
        ) else {
            preconditionFailure("Expected a safe placement")
        }

        precondition(center.y > source.maxY)
    }

    static func hoverBubbleStaysInsideNegativeOriginDisplay() {
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let word = CGRect(x: -1900, y: 1040, width: 65, height: 20)
        let size = CGSize(width: 300, height: 134)

        guard let center = OverlayLayout.hoverCenter(
            wordFrame: word,
            estimatedSize: size,
            screenFrame: screen
        ) else {
            preconditionFailure("Expected a safe placement")
        }
        let bubble = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        precondition(screen.contains(bubble))
        precondition(!bubble.intersects(word))
    }

    static func hoverBubbleFallsBackWhenDenseTextBlocksEveryPreferredPosition() {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let word = CGRect(x: 690, y: 430, width: 60, height: 22)
        let densePage = [
            CGRect(x: 0, y: 0, width: 1_440, height: 420),
            CGRect(x: 0, y: 480, width: 1_440, height: 420),
            CGRect(x: 0, y: 0, width: 660, height: 900),
            CGRect(x: 780, y: 0, width: 660, height: 900)
        ]
        let size = CGSize(width: 300, height: 134)

        guard let center = OverlayLayout.hoverCenter(
            wordFrame: word,
            estimatedSize: size,
            screenFrame: screen,
            obstacles: densePage
        ) else {
            preconditionFailure("Meaning bubble must not disappear on dense pages")
        }
        let bubble = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        precondition(screen.contains(bubble))
        precondition(!bubble.intersects(word))
    }
}
