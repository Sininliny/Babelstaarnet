import CoreGraphics

enum OverlayLayout {
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
        let insetScreen = screenFrame.insetBy(dx: 8, dy: 8)
        let expandedObstacles = obstacles.map {
            $0.insetBy(dx: -3, dy: -3)
        }

        for candidate in candidates {
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
            let bubble = CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            )

            guard insetScreen.contains(bubble),
                  !expandedObstacles.contains(where: bubble.intersects) else {
                continue
            }
            return center
        }

        return nil
    }
}
