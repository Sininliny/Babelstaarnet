import CoreGraphics
import Foundation

enum BubbleInteractionPolicy {
    static let stationaryTolerance: CGFloat = 3
    static let stationaryPinDelay: TimeInterval = 0.75

    static func pointerIsStationary(
        _ point: CGPoint,
        since anchor: CGPoint?
    ) -> Bool {
        guard let anchor else {
            return false
        }
        return hypot(point.x - anchor.x, point.y - anchor.y)
            <= stationaryTolerance
    }

    static func shouldPinAfterStationaryHover(
        point: CGPoint,
        anchor: CGPoint?,
        elapsed: TimeInterval,
        sourceFrame: CGRect
    ) -> Bool {
        sourceFrame.insetBy(dx: -8, dy: -8).contains(point)
            && pointerIsStationary(point, since: anchor)
            && elapsed >= stationaryPinDelay
    }

    static func shouldReleaseTemporaryHold(
        pointerMoved: Bool,
        idleDuration: TimeInterval
    ) -> Bool {
        pointerMoved || idleDuration < 0.12
    }

    static func preservedFrame(
        oldFrame: CGRect,
        newSize: CGSize,
        screenFrame: CGRect
    ) -> CGRect {
        let safeScreen = screenFrame.insetBy(dx: 8, dy: 8)
        let proposed = CGRect(
            x: oldFrame.minX,
            y: oldFrame.maxY - newSize.height,
            width: newSize.width,
            height: newSize.height
        )
        let x = min(
            max(proposed.minX, safeScreen.minX),
            safeScreen.maxX - proposed.width
        )
        let y = min(
            max(proposed.minY, safeScreen.minY),
            safeScreen.maxY - proposed.height
        )
        return CGRect(origin: CGPoint(x: x, y: y), size: newSize)
    }
}
