import BabelCore
import Combine
import CoreGraphics

enum BridgeFeedbackConfirmation: Equatable {
    case markedKnown
    case englishRestored
}

@MainActor
final class OverlayState: ObservableObject {
    @Published var hoverCard: HoverCard?
    @Published var isPinned = false
    @Published var feedbackConfirmation: BridgeFeedbackConfirmation?
    @Published private(set) var knownAnimationID = 0
    var onKnown: () -> Void = {}
    var onDontKnow: () -> Void = {}
    var onTogglePin: () -> Void = {}

    /// Publishing is what redraws both bubbles, and an unchanged value redraws
    /// them just as thoroughly as a changed one. This is written from the mouse
    /// timer, so it is written twenty times a second — and while no bubble is
    /// on screen it is written to the same value every single time.
    func setPinned(_ pinned: Bool) {
        guard isPinned != pinned else {
            return
        }
        isPinned = pinned
    }

    /// Records an action the reader has just taken. It stays until the word
    /// under the pointer changes; nothing clears it on a timer, because it
    /// describes the word rather than the keypress. The controller decides
    /// which word it belongs to and how long it survives — see
    /// `BridgeFeedbackMemory`.
    func showFeedback(_ confirmation: BridgeFeedbackConfirmation) {
        feedbackConfirmation = confirmation
        if confirmation == .markedKnown {
            knownAnimationID &+= 1
        }
    }

    /// Shows what the reader did to this word previously, without replaying the
    /// lift and glow that answered the press itself.
    func restoreFeedback(_ confirmation: BridgeFeedbackConfirmation?) {
        feedbackConfirmation = confirmation
    }

    func clearFeedback() {
        feedbackConfirmation = nil
    }
}

enum WordBubbleMetrics {
    static let width: CGFloat = 280

    static func fittedSize(_ fittingSize: CGSize) -> CGSize {
        CGSize(
            width: width,
            height: max(ceil(fittingSize.height), 54)
        )
    }
}

enum SentenceBubbleMetrics {
    static let width: CGFloat = 420

    static func fittedSize(_ fittingSize: CGSize) -> CGSize {
        CGSize(
            width: width,
            height: max(ceil(fittingSize.height), 76)
        )
    }
}
