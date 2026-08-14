import CoreGraphics
import BabelCore
import BabelLexicon
import BabelOCR
import BabelSpeech
import BabelTranslate
import LanguageDanish

struct LearningBubbleCenters: Equatable {
    let word: CGPoint
    let sentence: CGPoint
}

enum OverlayLayout {
    static func learningBubbleCenters(
        wordFrame: CGRect,
        sourceFrame: CGRect,
        wordSize: CGSize,
        sentenceSize: CGSize,
        screenFrame: CGRect
    ) -> LearningBubbleCenters? {
        let gap: CGFloat = 9
        let preferredWordCandidates = centers(
            around: wordFrame,
            size: wordSize,
            gap: gap,
            order: [.above, .right, .left, .below]
        )
        let highStackWordCandidate = CGPoint(
            x: wordFrame.midX,
            y: sourceFrame.maxY
                + gap
                + sentenceSize.height
                + gap
                + wordSize.height / 2
        )
        let wordCandidates = preferredWordCandidates
            + [highStackWordCandidate]
        let alignedSentenceCandidates = [
            CGPoint(
                x: wordFrame.midX,
                y: sourceFrame.minY - gap - sentenceSize.height / 2
            ),
            CGPoint(
                x: wordFrame.midX,
                y: sourceFrame.maxY + gap + sentenceSize.height / 2
            )
        ]
        let preferredSentenceCandidates = alignedSentenceCandidates + centers(
            around: sourceFrame,
            size: sentenceSize,
            gap: gap,
            order: [.below, .above, .right, .left]
        )

        for wordCandidate in wordCandidates {
            guard let wordCenter = safeCenter(
                wordCandidate,
                size: wordSize,
                screenFrame: screenFrame,
                obstacles: [sourceFrame]
            ) else {
                continue
            }
            let wordBubbleFrame = frame(center: wordCenter, size: wordSize)
            let stackedSentenceCandidates = centers(
                around: sourceFrame.union(wordBubbleFrame),
                size: sentenceSize,
                gap: gap,
                order: [.below, .above, .right, .left]
            )

            for sentenceCandidate in preferredSentenceCandidates
                + stackedSentenceCandidates {
                guard let sentenceCenter = safeCenter(
                    sentenceCandidate,
                    size: sentenceSize,
                    screenFrame: screenFrame,
                    obstacles: [sourceFrame, wordBubbleFrame]
                ) else {
                    continue
                }
                let sentenceBubbleFrame = frame(
                    center: sentenceCenter,
                    size: sentenceSize
                )
                guard wordBubbleFrame.minY
                        >= sentenceBubbleFrame.maxY + gap / 2 else {
                    continue
                }
                return LearningBubbleCenters(
                    word: wordCenter,
                    sentence: sentenceCenter
                )
            }
        }
        return nil
    }

    static func translationCenter(
        sourceFrame: CGRect,
        estimatedSize: CGSize,
        screenFrame: CGRect,
        obstacles: [CGRect] = []
    ) -> CGPoint? {
        let gap: CGFloat = 7
        let halfWidth = estimatedSize.width / 2
        let halfHeight = estimatedSize.height / 2

        let candidates = [
            CGPoint(
                x: sourceFrame.midX,
                y: sourceFrame.minY - gap - halfHeight
            ),
            CGPoint(
                x: sourceFrame.midX,
                y: sourceFrame.maxY + gap + halfHeight
            ),
            CGPoint(
                x: sourceFrame.maxX + gap + halfWidth,
                y: sourceFrame.midY
            ),
            CGPoint(
                x: sourceFrame.minX - gap - halfWidth,
                y: sourceFrame.midY
            )
        ]
        return firstSafeCenter(
            candidates: candidates,
            size: estimatedSize,
            screenFrame: screenFrame,
            obstacles: obstacles.isEmpty ? [sourceFrame] : obstacles
        )
    }

    static func hoverCenter(
        wordFrame: CGRect,
        estimatedSize: CGSize,
        screenFrame: CGRect,
        obstacles: [CGRect] = []
    ) -> CGPoint? {
        let gap: CGFloat = 12
        let halfWidth = estimatedSize.width / 2
        let halfHeight = estimatedSize.height / 2

        let candidates = [
            CGPoint(
                x: wordFrame.midX,
                y: wordFrame.maxY + gap + halfHeight
            ),
            CGPoint(
                x: wordFrame.midX,
                y: wordFrame.minY - gap - halfHeight
            ),
            CGPoint(
                x: wordFrame.maxX + gap + halfWidth,
                y: wordFrame.midY
            ),
            CGPoint(
                x: wordFrame.minX - gap - halfWidth,
                y: wordFrame.midY
            )
        ]
        if let center = firstSafeCenter(
            candidates: candidates,
            size: estimatedSize,
            screenFrame: screenFrame,
            obstacles: obstacles.isEmpty ? [wordFrame] : obstacles
        ) {
            return center
        }

        return firstSafeCenter(
            candidates: candidates,
            size: estimatedSize,
            screenFrame: screenFrame,
            obstacles: [wordFrame]
        )
    }

    private static func firstSafeCenter(
        candidates: [CGPoint],
        size: CGSize,
        screenFrame: CGRect,
        obstacles: [CGRect]
    ) -> CGPoint? {
        for candidate in candidates {
            if let center = safeCenter(
                candidate,
                size: size,
                screenFrame: screenFrame,
                obstacles: obstacles
            ) {
                return center
            }
        }

        return nil
    }

    private enum Side {
        case above
        case below
        case right
        case left
    }

    private static func centers(
        around anchor: CGRect,
        size: CGSize,
        gap: CGFloat,
        order: [Side]
    ) -> [CGPoint] {
        order.map { side in
            switch side {
            case .above:
                CGPoint(
                    x: anchor.midX,
                    y: anchor.maxY + gap + size.height / 2
                )
            case .below:
                CGPoint(
                    x: anchor.midX,
                    y: anchor.minY - gap - size.height / 2
                )
            case .right:
                CGPoint(
                    x: anchor.maxX + gap + size.width / 2,
                    y: anchor.midY
                )
            case .left:
                CGPoint(
                    x: anchor.minX - gap - size.width / 2,
                    y: anchor.midY
                )
            }
        }
    }

    private static func safeCenter(
        _ candidate: CGPoint,
        size: CGSize,
        screenFrame: CGRect,
        obstacles: [CGRect]
    ) -> CGPoint? {
        let insetScreen = screenFrame.insetBy(dx: 8, dy: 8)
        guard size.width <= insetScreen.width,
              size.height <= insetScreen.height else {
            return nil
        }
        let center = CGPoint(
            x: min(
                max(candidate.x, insetScreen.minX + size.width / 2),
                insetScreen.maxX - size.width / 2
            ),
            y: min(
                max(candidate.y, insetScreen.minY + size.height / 2),
                insetScreen.maxY - size.height / 2
            )
        )
        let bubble = frame(center: center, size: size)
        let expandedObstacles = obstacles.map {
            $0.insetBy(dx: -3, dy: -3)
        }
        guard insetScreen.contains(bubble),
              !expandedObstacles.contains(where: bubble.intersects) else {
            return nil
        }
        return center
    }

    private static func frame(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
