import BabelCore
import CoreGraphics
import Foundation

struct CursorVelocity: Equatable, Sendable {
    var dx: CGFloat
    var dy: CGFloat

    static let zero = CursorVelocity(dx: 0, dy: 0)

    var speed: CGFloat {
        hypot(dx, dy)
    }
}

enum AdaptiveCapturePlanner {
    static func captureFrame(
        around cursor: CGPoint,
        on screenFrame: CGRect,
        estimatedTextHeight: CGFloat?,
        velocity: CursorVelocity,
        expansion: CGFloat = 1
    ) -> CGRect {
        let textHeight = min(max(estimatedTextHeight ?? 22, 8), 96)
        let baseWidth = min(max(620, textHeight * 18), 1_420)
        let baseHeight = min(max(250, textHeight * 7.5), 820)
        let speedGrowth = min(1 + velocity.speed / 2_800, 1.32)
        let width = min(
            baseWidth * speedGrowth * expansion,
            screenFrame.width
        )
        let height = min(
            baseHeight * min(speedGrowth, 1.18) * expansion,
            screenFrame.height
        )

        let lookAheadLimit = min(width * 0.18, velocity.speed * 0.12)
        let magnitude = max(velocity.speed, 1)
        let center = CGPoint(
            x: cursor.x + (velocity.dx / magnitude * lookAheadLimit),
            y: cursor.y + (velocity.dy / magnitude * lookAheadLimit)
        )

        let proposed = CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
        return clamp(proposed, to: screenFrame)
    }

    static func sourceRect(
        for captureFrame: CGRect,
        on screenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: captureFrame.minX - screenFrame.minX,
            y: screenFrame.maxY - captureFrame.maxY,
            width: captureFrame.width,
            height: captureFrame.height
        )
    }

    static func shouldExpand(
        regions: [TextRegion],
        captureFrame: CGRect
    ) -> Bool {
        let words = regions.flatMap(\.words)
        guard !words.isEmpty else {
            return true
        }
        guard words.count <= 2 else {
            return false
        }

        let margin = max(
            12,
            words.map(\.frame.height).sorted()[
                words.count / 2
            ]
        )
        return words.contains {
            $0.frame.minX <= captureFrame.minX + margin
                || $0.frame.maxX >= captureFrame.maxX - margin
                || $0.frame.minY <= captureFrame.minY + margin
                || $0.frame.maxY >= captureFrame.maxY - margin
        }
    }

    static func estimatedTextHeight(
        from regions: [TextRegion],
        previous: CGFloat?
    ) -> CGFloat? {
        let heights = regions
            .flatMap(\.words)
            .map(\.frame.height)
            .filter { $0 >= 4 && $0 <= 180 }
            .sorted()
        guard !heights.isEmpty else {
            return previous
        }
        let median = heights[heights.count / 2]
        guard let previous else {
            return median
        }
        return previous * 0.65 + median * 0.35
    }

    private static func clamp(
        _ rect: CGRect,
        to bounds: CGRect
    ) -> CGRect {
        let x = min(
            max(rect.minX, bounds.minX),
            bounds.maxX - rect.width
        )
        let y = min(
            max(rect.minY, bounds.minY),
            bounds.maxY - rect.height
        )
        return CGRect(
            x: x,
            y: y,
            width: rect.width,
            height: rect.height
        )
    }
}
