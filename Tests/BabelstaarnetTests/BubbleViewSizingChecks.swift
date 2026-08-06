import AppKit
import SwiftUI

@main
@MainActor
enum BubbleViewSizingChecks {
    static func main() {
        let word = WordRegion(
            sourceText: "studieboliger",
            translatedText: "student accommodation",
            frame: CGRect(x: 100, y: 100, width: 70, height: 24),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            displayID: 1
        )
        let state = OverlayState()
        let wordHostingView = NSHostingView(
            rootView: WordBubbleView(state: state)
        )
        let sentenceHostingView = NSHostingView(
            rootView: SentenceBridgeBubbleView(state: state)
        )

        let compact = HoverCard(
            word: word,
            wordEnglishMeaning: "student accommodation",
            wordBridgeText: "En bolig til students.",
            wordBridgeEnglishTokenIndexes: [3],
            learningText: "Noget som hører til Earth.",
            adaptiveEnglishTokenIndexes: [4]
        )
        let wordHeight = measuredWordHeight(
            compact,
            state: state,
            hostingView: wordHostingView
        )
        let compactHeight = measuredSentenceHeight(
            compact,
            state: state,
            hostingView: sentenceHostingView
        )

        let supported = HoverCard(
            word: word,
            wordEnglishMeaning: "student accommodation",
            wordBridgeText: "En bolig til students.",
            wordBridgeEnglishTokenIndexes: [3],
            learningText: "Noget som hører til Earth.",
            englishSupport: "Relating to Earth or belonging to the planet.",
            adaptiveEnglishTokenIndexes: [4]
        )
        let supportedHeight = measuredSentenceHeight(
            supported,
            state: state,
            hostingView: sentenceHostingView
        )
        let translatedWordHeight = measuredWordHeight(
            supported,
            state: state,
            hostingView: wordHostingView
        )
        let wordOnlyCard = HoverCard(
            word: word,
            wordEnglishMeaning: "student accommodation",
            wordBridgeText: "En bolig til students.",
            wordBridgeEnglishTokenIndexes: [3],
            learningText: "Noget som hører til Earth.",
            englishSupport: "Relating to Earth or belonging to the planet.",
            adaptiveEnglishTokenIndexes: [4],
            showsControlsInWordBridge: true
        )
        let wordOnlyHeight = measuredWordHeight(
            wordOnlyCard,
            state: state,
            hostingView: wordHostingView
        )
        let sentenceOnlyCard = HoverCard(
            word: word,
            wordBridgeText: "En bolig til students.",
            wordBridgeEnglishTokenIndexes: [3],
            learningText: "Noget som hører til Earth.",
            englishSupport: "Relating to Earth or belonging to the planet.",
            adaptiveEnglishTokenIndexes: [4],
            showsControlsInSentenceBridge: true,
            showsEnglishSupportInSentenceBridge: true
        )
        let sentenceOnlyHeight = measuredSentenceHeight(
            sentenceOnlyCard,
            state: state,
            hostingView: sentenceHostingView
        )

        precondition(wordHeight >= 42)
        precondition(wordHeight < 140)
        precondition(translatedWordHeight > wordHeight)
        precondition(translatedWordHeight < 170)
        precondition(wordOnlyHeight > translatedWordHeight)
        precondition(wordOnlyHeight < 230)
        precondition(compactHeight >= 76)
        precondition(compactHeight < 140)
        precondition(supportedHeight == compactHeight)
        precondition(supportedHeight < 180)
        precondition(sentenceOnlyHeight > compactHeight)
        precondition(sentenceOnlyHeight < 200)
        print(
            "Two-bubble content sizing checks passed "
                + "(word \(translatedWordHeight), sentence \(compactHeight), "
                + "word-only \(wordOnlyHeight), sentence-only "
                + "\(sentenceOnlyHeight))"
        )

        let both = LearningBridgeConfiguration.both
        precondition(both.showsWordBridge)
        precondition(both.showsSentenceBridge)
        precondition(both.hasVisibleBridge)
        let wordOnly = LearningBridgeConfiguration(
            showsWordBridge: true,
            showsSentenceBridge: false
        )
        let data = try! JSONEncoder().encode(wordOnly)
        precondition(
            try! JSONDecoder().decode(
                LearningBridgeConfiguration.self,
                from: data
            ) == wordOnly
        )

        let initialAnimationID = state.knownAnimationID
        state.showFeedback(.markedKnown)
        precondition(state.feedbackConfirmation == .markedKnown)
        precondition(state.knownAnimationID == initialAnimationID + 1)
        state.showFeedback(.englishRestored)
        precondition(state.feedbackConfirmation == .englishRestored)
        precondition(state.knownAnimationID == initialAnimationID + 1)
        state.clearFeedback()
        precondition(state.feedbackConfirmation == nil)

        let opacities = (0...5).map(KnowledgeTone.opacity(for:))
        precondition(opacities == opacities.sorted(by: >))
        precondition(opacities[0] - opacities[5] < 0.30)

        let interlinear = InterlinearBridgePresentation.units(
            text: "Hun tøvede hesitated, før hun svarede.",
            englishTokenIndexes: [2]
        )
        precondition(interlinear[1].danish == "tøvede,")
        precondition(interlinear[1].english == "hesitated")
        precondition(interlinear.map(\.danish).compactMap { $0 }
            == ["Hun", "tøvede,", "før", "hun", "svarede."])
    }

    private static func measuredWordHeight(
        _ card: HoverCard,
        state: OverlayState,
        hostingView: NSHostingView<WordBubbleView>
    ) -> CGFloat {
        state.hoverCard = card
        hostingView.rootView = WordBubbleView(state: state)
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        return WordBubbleMetrics.fittedSize(hostingView.fittingSize).height
    }

    private static func measuredSentenceHeight(
        _ card: HoverCard,
        state: OverlayState,
        hostingView: NSHostingView<SentenceBridgeBubbleView>
    ) -> CGFloat {
        state.hoverCard = card
        hostingView.rootView = SentenceBridgeBubbleView(state: state)
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        return SentenceBubbleMetrics.fittedSize(hostingView.fittingSize).height
    }
}
