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
    private var feedbackClearTask: Task<Void, Never>?

    func showFeedback(_ confirmation: BridgeFeedbackConfirmation) {
        feedbackClearTask?.cancel()
        feedbackConfirmation = confirmation
        if confirmation == .markedKnown {
            knownAnimationID &+= 1
        }
        feedbackClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.feedbackConfirmation = nil
            self?.feedbackClearTask = nil
        }
    }

    func clearFeedback() {
        feedbackClearTask?.cancel()
        feedbackClearTask = nil
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
