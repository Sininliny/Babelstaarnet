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
        let directMeaningOnly = HoverCard(
            word: word,
            wordEnglishMeaning: "student accommodation",
            learningText: "Noget som hører til Earth."
        )
        let directMeaningOnlyHeight = measuredWordHeight(
            directMeaningOnly,
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
            adaptiveEnglishTokenIndexes: [4]
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
            showsEnglishSupportInSentenceBridge: true
        )
        let sentenceOnlyHeight = measuredSentenceHeight(
            sentenceOnlyCard,
            state: state,
            hostingView: sentenceHostingView
        )
        let testingSentenceOnlyCard = HoverCard(
            word: word,
            wordKnowledgeLevel: 3,
            wordEnglishMeaning: "student accommodation",
            learningText: "Mange studieboliger står tomme.",
            showsEnglishSupportInSentenceBridge: true
        )
        let testingSentenceOnlyHeight = measuredSentenceHeight(
            testingSentenceOnlyCard,
            state: state,
            hostingView: sentenceHostingView
        )

        // The feedback row is fixed above the answer, so a hover that is only
        // passing over a word and one the reader has settled on are the same
        // bubble at the same size. That equality is the whole point: a row
        // that never comes or goes cannot flicker, and the answer underneath
        // it never reflows.
        let passiveCard = HoverCard(
            word: word,
            wordEnglishMeaning: "student accommodation",
            wordBridgeText: "En bolig til students.",
            wordBridgeEnglishTokenIndexes: [3],
            learningText: "Noget som hører til Earth.",
            englishSupport: "Relating to Earth or belonging to the planet.",
            adaptiveEnglishTokenIndexes: [4]
        )
        let passiveHeight = measuredWordHeight(
            passiveCard,
            state: state,
            hostingView: wordHostingView
        )
        precondition(
            passiveHeight == wordOnlyHeight,
            "The feedback row must not change the bubble between a passing "
                + "hover and a settled one"
        )

        // Requesting all English keeps the bubble in the same shape; it changes
        // what is glossed, not how much chrome the learner has to read past.
        let allEnglishCard = HoverCard(
            word: word,
            wordEnglishMeaning: "student accommodation",
            wordBridgeText: "En bolig til students.",
            wordBridgeEnglishTokenIndexes: [3],
            learningText: "Noget som hører til Earth.",
            adaptiveEnglishTokenIndexes: [4],
            showsAllEnglish: true
        )
        let allEnglishHeight = measuredWordHeight(
            allEnglishCard,
            state: state,
            hostingView: wordHostingView
        )
        precondition(allEnglishHeight == wordHeight)

        precondition(wordHeight >= 42)
        precondition(wordHeight < 140)
        precondition(directMeaningOnlyHeight < wordHeight)
        precondition(translatedWordHeight > wordHeight)
        precondition(translatedWordHeight < 170)
        precondition(wordOnlyHeight == translatedWordHeight)
        precondition(wordOnlyHeight < 230)
        precondition(compactHeight >= 76)
        precondition(compactHeight < 140)
        precondition(supportedHeight == compactHeight)
        precondition(supportedHeight < 180)
        precondition(sentenceOnlyHeight < 200)
        precondition(testingSentenceOnlyHeight < 200)

        // English support still has to earn its room. Measured on a line long
        // enough to clear the panel's minimum height, since below that floor
        // every difference is clamped away and nothing is being tested.
        let longLine = String(
            repeating: "Mange studieboliger står tomme fordi de ligger langt "
                + "fra byen og fra de uddannelsessteder de blev bygget til. ",
            count: 4
        )
        let plainSentence = HoverCard(
            word: word,
            learningText: longLine
        )
        let supportedSentence = HoverCard(
            word: word,
            learningText: longLine,
            englishSupport: "Relating to Earth or belonging to the planet.",
            showsEnglishSupportInSentenceBridge: true
        )
        let plainSentenceHeight = measuredSentenceHeight(
            plainSentence,
            state: state,
            hostingView: sentenceHostingView
        )
        let supportedSentenceHeight = measuredSentenceHeight(
            supportedSentence,
            state: state,
            hostingView: sentenceHostingView
        )
        precondition(
            plainSentenceHeight > SentenceBubbleMetrics.fittedSize(.zero).height,
            "The fixture is still clamped to the panel minimum"
        )
        precondition(
            supportedSentenceHeight > plainSentenceHeight,
            "English support did not add a row to the sentence panel"
        )
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

        // English stands in the line instead of under it, so every token
        // belongs to one language and nothing is paired. A Danish word worth
        // several English ones stays a single substitution.
        let substituted = InterlinearBridgePresentation.units(
            text: "Hun the period of reflection, før hun svarede.",
            englishTokenIndexes: [1, 2, 3, 4]
        )
        precondition(substituted.count == 5)
        precondition(substituted[0].danish == "Hun")
        precondition(substituted[0].english == nil)
        precondition(substituted[1].danish == nil)
        precondition(
            substituted[1].english == "the period of reflection,",
            "One substitution split into several: "
                + String(describing: substituted[1].english)
        )
        precondition(
            substituted.compactMap(\.danish)
                == ["Hun", "før", "hun", "svarede."]
        )
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
