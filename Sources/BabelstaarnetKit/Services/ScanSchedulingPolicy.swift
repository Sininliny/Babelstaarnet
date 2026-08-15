import BabelCore
import CoreGraphics
import Foundation

enum ScanSchedulingPolicy {
    static func shouldReplaceActiveScan(
        origin: CGPoint,
        current: CGPoint,
        estimatedTextHeight: CGFloat?
    ) -> Bool {
        let textHeight = min(max(estimatedTextHeight ?? 22, 8), 96)
        let threshold = min(max(textHeight * 1.35, 24), 72)
        return hypot(current.x - origin.x, current.y - origin.y)
            >= threshold
    }

    static func canReuseRecognizedWord(
        at cursor: CGPoint,
        in regions: [TextRegion],
        resultAge: TimeInterval,
        refreshInterval: TimeInterval
    ) -> Bool {
        guard resultAge >= 0,
              resultAge < refreshInterval else {
            return false
        }
        return HoverHitTesting.word(
            at: cursor,
            in: regions,
            retaining: nil
        ) != nil
    }
}
