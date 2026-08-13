import CoreGraphics
import Foundation

/// Reading is the task; rating vocabulary is not. The bridge therefore asks
/// nothing while the pointer is passing over text, and offers its controls only
/// once the learner has deliberately settled on a word — by pinning, holding
/// the modifier, or resting long enough that the bubble holds itself.
///
/// The shortcuts stay live the whole time, so nothing is slower for someone who
/// already knows them; the buttons are a discovery aid, not a prompt.
///
/// Settling is a latch, not a level. The temporary hold that earns it is
/// released by *any* system input — a keystroke, a scroll, a fingertip resting
/// on a trackpad — and is then re-earned only after another three quarters of a
/// second of complete stillness. Someone reading a page with the pointer parked
/// on a word generates that pattern constantly, so the controls appeared and
/// vanished repeatedly underneath a reader who had never left the word. Once
/// they are earned they therefore stay until the pointer moves to something
/// else: retracting a control the reader may be reaching for is a worse failure
/// than showing one they did not ask for.
enum BridgeAttentionPolicy {
    static func showsFeedbackControls(
        bubbleIsHeld: Bool,
        hasSettledOnWord: Bool
    ) -> Bool {
        bubbleIsHeld || hasSettledOnWord
    }
}

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

    static func shouldKeepLearningSnapshot(
        pointer: CGPoint,
        anchor: CGPoint?,
        interactionIsHeld: Bool
    ) -> Bool {
        interactionIsHeld || pointerIsStationary(pointer, since: anchor)
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

    /// Which edge stays put when a visible bubble changes height. A bubble
    /// resting above the source line has to grow upwards, or it expands over
    /// the very text the reader is looking at.
    enum GrowthAnchor {
        case top
        case bottom

        static func growingAwayFrom(
            sourceFrame: CGRect,
            bubbleFrame: CGRect
        ) -> Self {
            bubbleFrame.midY >= sourceFrame.midY ? .bottom : .top
        }
    }

    static func preservedFrame(
        oldFrame: CGRect,
        newSize: CGSize,
        screenFrame: CGRect,
        anchoring anchor: GrowthAnchor = .top
    ) -> CGRect {
        let safeScreen = screenFrame.insetBy(dx: 8, dy: 8)
        let proposed = CGRect(
            x: oldFrame.minX,
            y: anchor == .top
                ? oldFrame.maxY - newSize.height
                : oldFrame.minY,
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
