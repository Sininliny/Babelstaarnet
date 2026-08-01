import Combine
import CoreGraphics

@MainActor
final class OverlayState: ObservableObject {
    @Published var hoverCard: HoverCard?
    @Published var isPinned = false
    @Published var isStationaryHeld = false
    @Published var isOptionHeld = false
    var onKnown: () -> Void = {}
    var onDontKnow: () -> Void = {}
}

enum HoverBubbleMetrics {
    static let width: CGFloat = 320

    static func fittedSize(_ fittingSize: CGSize) -> CGSize {
        CGSize(
            width: width,
            height: min(max(ceil(fittingSize.height), 54), 360)
        )
    }
}
