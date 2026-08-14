import CoreGraphics
@testable import BabelstaarnetKit

@main
struct OverlayLayoutChecks {
    static func main() {
        pairedLearningBubblesStaySeparateFromTextAndEachOther()
        pairedBubblesStackSafelyNearScreenEdge()
        pairedBubblesKeepTheirOrderNearLowerScreenEdge()
        translationBubbleNeverCoversSourceWhenThereIsRoomBelow()
        translationBubbleMovesAboveNearBottomEdge()
        hoverBubbleStaysInsideNegativeOriginDisplay()
        hoverBubbleFallsBackWhenDenseTextBlocksEveryPreferredPosition()
        print("Overlay layout checks passed")
    }

    static func pairedLearningBubblesStaySeparateFromTextAndEachOther() {
        let word = CGRect(x: 610, y: 430, width: 72, height: 24)
        let source = CGRect(x: 430, y: 426, width: 520, height: 32)
        let wordSize = CGSize(width: 280, height: 64)
        let sentenceSize = CGSize(width: 420, height: 126)
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)

        guard let centers = OverlayLayout.learningBubbleCenters(
            wordFrame: word,
            sourceFrame: source,
            wordSize: wordSize,
            sentenceSize: sentenceSize,
            screenFrame: screen
        ) else {
            preconditionFailure("Expected two safe learning bubble positions")
        }
        let wordBubble = CGRect(
            x: centers.word.x - wordSize.width / 2,
            y: centers.word.y - wordSize.height / 2,
            width: wordSize.width,
            height: wordSize.height
        )
        let sentenceBubble = CGRect(
            x: centers.sentence.x - sentenceSize.width / 2,
            y: centers.sentence.y - sentenceSize.height / 2,
            width: sentenceSize.width,
            height: sentenceSize.height
        )
        precondition(screen.contains(wordBubble))
        precondition(screen.contains(sentenceBubble))
        precondition(!wordBubble.intersects(source))
        precondition(!sentenceBubble.intersects(source))
        precondition(!wordBubble.intersects(sentenceBubble))
        precondition(wordBubble.minY > sentenceBubble.maxY)
        precondition(wordBubble.midY > source.midY)
        precondition(sentenceBubble.midY < source.midY)
        precondition(abs(centers.word.x - centers.sentence.x) < 0.5)
    }

    static func pairedBubblesStackSafelyNearScreenEdge() {
        let screen = CGRect(x: 0, y: 0, width: 900, height: 700)
        let source = CGRect(x: 8, y: 650, width: 884, height: 28)
        let word = CGRect(x: 420, y: 652, width: 70, height: 24)
        let wordSize = CGSize(width: 280, height: 64)
        let sentenceSize = CGSize(width: 420, height: 126)

        guard let centers = OverlayLayout.learningBubbleCenters(
            wordFrame: word,
            sourceFrame: source,
            wordSize: wordSize,
            sentenceSize: sentenceSize,
            screenFrame: screen
        ) else {
            preconditionFailure("Edge placement should stack both bubbles")
        }
        let wordBubble = CGRect(
            x: centers.word.x - wordSize.width / 2,
            y: centers.word.y - wordSize.height / 2,
            width: wordSize.width,
            height: wordSize.height
        )
        let sentenceBubble = CGRect(
            x: centers.sentence.x - sentenceSize.width / 2,
            y: centers.sentence.y - sentenceSize.height / 2,
            width: sentenceSize.width,
            height: sentenceSize.height
        )
        precondition(screen.contains(wordBubble))
        precondition(screen.contains(sentenceBubble))
        precondition(!wordBubble.intersects(source))
        precondition(!sentenceBubble.intersects(source))
        precondition(!wordBubble.intersects(sentenceBubble))
        precondition(wordBubble.minY > sentenceBubble.maxY)
    }

    static func pairedBubblesKeepTheirOrderNearLowerScreenEdge() {
        let screen = CGRect(x: 0, y: 0, width: 900, height: 700)
        let source = CGRect(x: 8, y: 12, width: 884, height: 28)
        let word = CGRect(x: 420, y: 14, width: 70, height: 24)
        let wordSize = CGSize(width: 280, height: 64)
        let sentenceSize = CGSize(width: 420, height: 126)

        guard let centers = OverlayLayout.learningBubbleCenters(
            wordFrame: word,
            sourceFrame: source,
            wordSize: wordSize,
            sentenceSize: sentenceSize,
            screenFrame: screen
        ) else {
            preconditionFailure("Lower-edge placement should keep both bubbles")
        }
        let wordBubble = CGRect(
            x: centers.word.x - wordSize.width / 2,
            y: centers.word.y - wordSize.height / 2,
            width: wordSize.width,
            height: wordSize.height
        )
        let sentenceBubble = CGRect(
            x: centers.sentence.x - sentenceSize.width / 2,
            y: centers.sentence.y - sentenceSize.height / 2,
            width: sentenceSize.width,
            height: sentenceSize.height
        )
        precondition(screen.contains(wordBubble))
        precondition(screen.contains(sentenceBubble))
        precondition(!wordBubble.intersects(source))
        precondition(!sentenceBubble.intersects(source))
        precondition(!wordBubble.intersects(sentenceBubble))
        precondition(wordBubble.minY > sentenceBubble.maxY)
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
