import CoreGraphics
@testable import BabelstaarnetKit

@main
struct OverlayLayoutChecks {
    static func main() {
        pairedLearningBubblesStaySeparateFromTextAndEachOther()
        theAnswerStaysNearTheWordOnEveryLineOfAParagraph()
        aWordAtTheColumnEdgeIsAnsweredInTheMargin()
        theFocusMarkUnderlinesTheWordWithoutCoveringIt()
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

    /// Neither panel may cover the paragraph being read, so a word in the
    /// middle of one is answered from its edge. Which edge is nearest depends
    /// on the line the word is on, and answering from a fixed one put the
    /// meaning of a word on the third line most of a screen away from it.
    static func theAnswerStaysNearTheWordOnEveryLineOfAParagraph() {
        let screen = CGRect(x: 0, y: 0, width: 1_920, height: 1_200)
        let paragraph = CGRect(x: 410, y: 600, width: 1_130, height: 200)
        let sentenceSize = CGSize(width: 420, height: 115)

        // Top line to bottom line, as the reader sees them.
        for lineY in [756, 700, 645, 600] {
            let word = CGRect(
                x: 1_000,
                y: CGFloat(lineY),
                width: 80,
                height: 22
            )
            let bubble = wordBubble(
                word: word,
                source: paragraph,
                sentenceSize: sentenceSize,
                screen: screen
            )
            // The panel may never end up further from the word than the height
            // of the panel whose room used to be reserved above it, which is
            // exactly the space that reservation was wasting.
            precondition(
                clearance(word, bubble) < sentenceSize.height,
                "line at \(lineY) answered \(clearance(word, bubble)) pt away"
            )
        }
    }

    /// With the paragraph filling the column, the space beside it is the
    /// nearest free space to a word at its edge — and lands the answer level
    /// with the line the word is on.
    static func aWordAtTheColumnEdgeIsAnsweredInTheMargin() {
        let screen = CGRect(x: 0, y: 0, width: 1_920, height: 1_200)
        let paragraph = CGRect(x: 410, y: 600, width: 1_130, height: 200)
        let sentenceSize = CGSize(width: 420, height: 115)

        for word in [
            CGRect(x: 1_450, y: 700, width: 80, height: 22),
            CGRect(x: 420, y: 700, width: 80, height: 22)
        ] {
            let bubble = wordBubble(
                word: word,
                source: paragraph,
                sentenceSize: sentenceSize,
                screen: screen
            )
            precondition(clearance(word, bubble) < 40)
            precondition(bubble.midY == word.midY)
        }
    }

    /// The mark says which word without obscuring any part of it: it sits
    /// entirely under the word's own box, and spans the word rather than some
    /// fixed width that would say "this one" about the wrong letters.
    static func theFocusMarkUnderlinesTheWordWithoutCoveringIt() {
        for word in [
            CGRect(x: 300, y: 400, width: 62, height: 15),
            CGRect(x: 0, y: 0, width: 8, height: 40)
        ] {
            let mark = WordFocusMarker.frame(under: word)
            precondition(mark.maxY <= word.minY + WordFocusMarker.glow)
            precondition(mark.height > 0)
            precondition(mark.width > word.width)
            // Centred on the word, so it underlines that word and not the one
            // beside it.
            precondition(abs(mark.midX - word.midX) < 0.001)
            // The rule itself, once the glow's margin is taken back off, is
            // clear of the word's box.
            let rule = mark.insetBy(dx: WordFocusMarker.glow, dy: WordFocusMarker.glow)
            precondition(rule.maxY <= word.minY - WordFocusMarker.drop + 0.001)
            precondition(rule.height == WordFocusMarker.thickness)
        }
    }

    /// The word panel's frame, with every invariant the pair must hold checked
    /// on the way out.
    private static func wordBubble(
        word: CGRect,
        source: CGRect,
        sentenceSize: CGSize,
        screen: CGRect
    ) -> CGRect {
        let wordSize = CGSize(width: 280, height: 130)
        guard let centers = OverlayLayout.learningBubbleCenters(
            wordFrame: word,
            sourceFrame: source,
            wordSize: wordSize,
            sentenceSize: sentenceSize,
            screenFrame: screen
        ) else {
            preconditionFailure("Expected a placement for \(word)")
        }
        let bubble = CGRect(
            x: centers.word.x - wordSize.width / 2,
            y: centers.word.y - wordSize.height / 2,
            width: wordSize.width,
            height: wordSize.height
        )
        let sentence = CGRect(
            x: centers.sentence.x - sentenceSize.width / 2,
            y: centers.sentence.y - sentenceSize.height / 2,
            width: sentenceSize.width,
            height: sentenceSize.height
        )
        precondition(screen.contains(bubble))
        precondition(screen.contains(sentence))
        precondition(!bubble.intersects(source))
        precondition(!sentence.intersects(source))
        precondition(!bubble.intersects(sentence))
        precondition(bubble.minY > sentence.maxY)
        return bubble
    }

    /// The clear space between the word and the panel answering about it.
    private static func clearance(_ rect: CGRect, _ other: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - other.maxX, other.minX - rect.maxX), 0)
        let dy = max(max(rect.minY - other.maxY, other.minY - rect.maxY), 0)
        return (dx * dx + dy * dy).squareRoot()
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
