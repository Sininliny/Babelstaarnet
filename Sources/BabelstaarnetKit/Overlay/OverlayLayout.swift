import CoreGraphics

struct LearningBubbleCenters: Equatable {
    let word: CGPoint
    let sentence: CGPoint
}

/// Where the mark naming the pointed-at word is drawn, on the page itself.
///
/// The panels cannot sit on the word — they would cover the sentence being
/// read — so on a paragraph they answer from its edge, and the reader was left
/// to work out which of the words in front of them was being answered about.
/// Pointing at a word and being handed a meaning somewhere off to the side is
/// only unambiguous while the pointer has not moved, and the reader's eye
/// leaves the pointer long before their hand does.
enum WordFocusMarker {
    static let thickness: CGFloat = 2
    /// Clear space under the word's own box, so the rule underlines the word
    /// rather than striking through its descenders.
    static let drop: CGFloat = 2
    /// Room around the rule for its glow to fade out in. Clipped at the panel
    /// edge, the glow reads as a second, harder line.
    static let glow: CGFloat = 4
    /// The rule runs a little past the word at each end, the way an underline
    /// drawn by hand does.
    static let overhang: CGFloat = 1

    /// The panel the rule is drawn in: the width of the word, sitting just
    /// under it, with the glow's room added on every side.
    static func frame(under wordFrame: CGRect) -> CGRect {
        CGRect(
            x: wordFrame.minX - overhang - glow,
            y: wordFrame.minY - drop - thickness - glow,
            width: wordFrame.width + (overhang + glow) * 2,
            height: thickness + glow * 2
        )
    }
}

enum OverlayLayout {
    /// Where the two panels go, in order of how far the word panel ends up
    /// from the word it is answering about.
    ///
    /// Neither panel may cover the sentence being read, and a sentence running
    /// over several lines is one block for that purpose. So a word in the
    /// middle of a paragraph cannot be answered beside itself, and the list
    /// below is what "as close as the block allows" means instead: the margin
    /// level with the word's own line first, then the edge of the block over
    /// the word's own column.
    ///
    /// Only the last candidate leaves the sentence panel's height free beneath
    /// the word panel. Reserving that room was the first thing tried, and the
    /// sentence panel then usually went *below* the block instead — so the
    /// answer was pushed a panel's height further up than anything needed,
    /// which on a four-line paragraph put it most of a screen from the word.
    static func learningBubbleCenters(
        wordFrame: CGRect,
        sourceFrame: CGRect,
        wordSize: CGSize,
        sentenceSize: CGSize,
        screenFrame: CGRect
    ) -> LearningBubbleCenters? {
        let gap: CGFloat = 9
        let besideTheBlockCandidates = [
            CGPoint(
                x: sourceFrame.maxX + gap + wordSize.width / 2,
                y: wordFrame.midY
            ),
            CGPoint(
                x: sourceFrame.minX - gap - wordSize.width / 2,
                y: wordFrame.midY
            )
        ]
        let againstTheBlockCandidates = [
            CGPoint(
                x: wordFrame.midX,
                y: sourceFrame.maxY + gap + wordSize.height / 2
            ),
            CGPoint(
                x: wordFrame.midX,
                y: sourceFrame.minY - gap - wordSize.height / 2
            )
        ]
        let highStackWordCandidate = CGPoint(
            x: wordFrame.midX,
            y: sourceFrame.maxY
                + gap
                + sentenceSize.height
                + gap
                + wordSize.height / 2
        )
        let wordCandidates = nearestFirst(
            centers(
                around: wordFrame,
                size: wordSize,
                gap: gap,
                order: [.above, .right, .left, .below]
            )
                + besideTheBlockCandidates
                + againstTheBlockCandidates
                + [highStackWordCandidate],
            size: wordSize,
            from: wordFrame
        )
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
        let avoiding = obstacles.isEmpty ? [wordFrame] : obstacles
        if let center = firstSafeCenter(
            candidates: candidates,
            size: estimatedSize,
            screenFrame: screenFrame,
            obstacles: avoiding
        ) {
            return center
        }

        // Nothing touching the word is free, which is what a word inside a
        // paragraph looks like. Before giving up and printing over the text
        // being read, the space around the paragraph is offered — still the
        // nearest position first, so a word on the last line is answered just
        // under its own block rather than above the whole of it.
        let block = avoiding.dropFirst().reduce(avoiding[0]) { $0.union($1) }
        if let center = firstSafeCenter(
            candidates: nearestFirst(
                centers(
                    around: block,
                    size: estimatedSize,
                    gap: gap,
                    order: [.above, .below, .right, .left]
                ) + [
                    CGPoint(
                        x: block.maxX + gap + estimatedSize.width / 2,
                        y: wordFrame.midY
                    ),
                    CGPoint(
                        x: block.minX - gap - estimatedSize.width / 2,
                        y: wordFrame.midY
                    ),
                    CGPoint(
                        x: wordFrame.midX,
                        y: block.maxY + gap + estimatedSize.height / 2
                    ),
                    CGPoint(
                        x: wordFrame.midX,
                        y: block.minY - gap - estimatedSize.height / 2
                    )
                ],
                size: estimatedSize,
                from: wordFrame
            ),
            size: estimatedSize,
            screenFrame: screenFrame,
            obstacles: avoiding
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

    /// The same candidates, tried nearest to the word first.
    ///
    /// Which position is nearest is not a property of the list: it depends on
    /// where in its paragraph the word sits. A word on the last line is nearest
    /// to the space under the block, a word on the first line to the space over
    /// it, and a word in a narrow column to the margin beside it. Fixing that
    /// order in advance means answering some words from the far side of the
    /// paragraph while a closer position sat free.
    ///
    /// Candidates within half a point of each other keep their listed order, so
    /// the four positions touching the word itself — all exactly one gap away —
    /// still resolve above, right, left, below.
    private static func nearestFirst(
        _ candidates: [CGPoint],
        size: CGSize,
        from wordFrame: CGRect
    ) -> [CGPoint] {
        candidates
            .enumerated()
            .sorted { left, right in
                let leftDistance = distance(
                    from: wordFrame,
                    to: frame(center: left.element, size: size)
                )
                let rightDistance = distance(
                    from: wordFrame,
                    to: frame(center: right.element, size: size)
                )
                if abs(leftDistance - rightDistance) > 0.5 {
                    return leftDistance < rightDistance
                }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    /// The clear space between two rectangles, which is zero where they touch.
    /// Centre to centre would rate a panel lying across the word as nearer than
    /// one resting neatly beside it.
    private static func distance(from rect: CGRect, to other: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - other.maxX, other.minX - rect.maxX), 0)
        let dy = max(max(rect.minY - other.maxY, other.minY - rect.maxY), 0)
        return hypot(dx, dy)
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
