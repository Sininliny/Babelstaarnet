import AppKit
import SwiftUI

@main
@MainActor
enum BubbleViewSizingChecks {
    static func main() {
        let word = WordRegion(
            sourceText: "Jordens",
            translatedText: "Earth's",
            beginnerExplanation: "Noget som hører til jorden.",
            adaptiveExplanation: "Noget som hører til Earth.",
            adaptiveEnglishTerms: ["Earth"],
            frame: CGRect(x: 100, y: 100, width: 70, height: 24),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            displayID: 1
        )
        let state = OverlayState()
        let hostingView = NSHostingView(
            rootView: OverlayRootView(state: state)
        )

        let compact = HoverCard(
            word: word,
            definition: "Noget som hører til Earth.",
            familiarityLabel: "Well established",
            translationMode: .english,
            explanationMode: .adaptive
        )
        let compactHeight = measuredHeight(
            compact,
            state: state,
            hostingView: hostingView
        )

        let supported = HoverCard(
            word: word,
            definition: "Noget som hører til Earth.",
            englishSupport: "Relating to Earth or belonging to the planet.",
            familiarityLabel: "New word",
            translationMode: .english,
            explanationMode: .adaptive
        )
        let supportedHeight = measuredHeight(
            supported,
            state: state,
            hostingView: hostingView
        )

        precondition(compactHeight >= 90)
        precondition(compactHeight < 150)
        precondition(supportedHeight > compactHeight)
        precondition(supportedHeight < 190)
        print(
            "Bubble content sizing checks passed "
                + "(compact \(compactHeight), supported \(supportedHeight))"
        )
    }

    private static func measuredHeight(
        _ card: HoverCard,
        state: OverlayState,
        hostingView: NSHostingView<OverlayRootView>
    ) -> CGFloat {
        state.hoverCard = card
        hostingView.rootView = OverlayRootView(state: state)
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        return HoverBubbleMetrics.fittedSize(hostingView.fittingSize).height
    }
}
