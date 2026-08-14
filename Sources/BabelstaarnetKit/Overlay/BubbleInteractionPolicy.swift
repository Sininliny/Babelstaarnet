import CoreGraphics
import Foundation
import BabelCore
import BabelLexicon
import BabelOCR
import BabelSpeech
import BabelTranslate
import LanguageDanish

/// The feedback controls are a fixed row at the top of the word panel and are
/// never conditional, so the policy that used to decide when to reveal them is
/// gone rather than left answering a question nothing asks.
///
/// It existed because the buttons were once drawn on every hover and read as a
/// demand; hiding them until the reader settled on a word was the answer. That
/// cure had its own fault. Settling was derived from the temporary hold, and
/// the hold is released by *any* system input — a keystroke, a scroll, a
/// fingertip resting on a trackpad — then re-earned only after another three
/// quarters of a second of complete stillness. Reading a page with the pointer
/// parked produces that pattern about once a second, so the row appeared and
/// vanished under a reader who had never left the word.
///
/// Position now does the work that hiding was doing: the row sits above the
/// answer, behind a rule, outside the column the meaning is read in. A fixed
/// row cannot flicker, and there is no state left to get wrong.
/// How long the bubble remembers that the reader acted on a word.
///
/// The confirmation began as a flash: a tick for 1.4 seconds and then nothing,
/// which made it a receipt for the keypress rather than a fact about the word.
/// It is a fact about the word. Coming back to a word and being told again that
/// you have already marked it is the point — otherwise the reader has to
/// remember, and remembering is the thing the app is supposed to be doing.
///
/// So nothing expires on a clock while the bubble is open, and returning to a
/// word inside the retention window finds the same answer still there. Only a
/// word met again after the window has passed comes back clean, which is long
/// enough that a reading session is one continuous state and short enough that
/// tomorrow's reading does not open covered in yesterday's ticks.
enum BridgeFeedbackMemory {
    static let retention: TimeInterval = 5 * 60

    /// Kept small deliberately: this is what the reader did minutes ago, not a
    /// history. The learner profile is where lasting knowledge lives.
    static let capacity = 256

    static func isRemembered(recordedAt: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(recordedAt)
        return age >= 0 && age < retention
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
