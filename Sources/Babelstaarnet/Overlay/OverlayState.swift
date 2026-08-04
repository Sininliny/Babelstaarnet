import Combine
import CoreGraphics

@MainActor
final class OverlayState: ObservableObject {
    @Published var hoverCard: HoverCard?
    @Published var isPinned = false
    var onKnown: () -> Void = {}
    var onDontKnow: () -> Void = {}
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
