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
        let testingSentenceOnlyCard = HoverCard(
            word: word,
            wordKnowledgeLevel: 3,
            wordEnglishMeaning: "student accommodation",
            learningText: "Mange studieboliger står tomme.",
            showsControlsInSentenceBridge: true,
            showsEnglishSupportInSentenceBridge: true
        )
        let testingSentenceOnlyHeight = measuredSentenceHeight(
            testingSentenceOnlyCard,
            state: state,
            hostingView: sentenceHostingView
        )

        // Passive reading must be quieter than a deliberate hold: the same word
        // gains the feedback row only once the learner settles on it.
        let passiveCard = HoverCard(
            word: word,
            wordEnglishMeaning: "student accommodation",
            wordBridgeText: "En bolig til students.",
            wordBridgeEnglishTokenIndexes: [3],
            learningText: "Noget som hører til Earth.",
            englishSupport: "Relating to Earth or belonging to the planet.",
            adaptiveEnglishTokenIndexes: [4],
            showsControlsInWordBridge: false
        )
        let passiveHeight = measuredWordHeight(
            passiveCard,
            state: state,
            hostingView: wordHostingView
        )
        precondition(
            passiveHeight < wordOnlyHeight,
            "A passing hover should not carry the feedback controls"
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
        precondition(wordOnlyHeight > translatedWordHeight)
        precondition(wordOnlyHeight < 230)
        precondition(compactHeight >= 76)
        precondition(compactHeight < 140)
        precondition(supportedHeight == compactHeight)
        precondition(supportedHeight < 180)
        precondition(sentenceOnlyHeight > compactHeight)
        precondition(sentenceOnlyHeight < 200)
        precondition(testingSentenceOnlyHeight > compactHeight)
        precondition(testingSentenceOnlyHeight < 200)
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

        // Words are translated one at a time, so the translator answers each of
        // them as though it opened a sentence. A capital under a lowercase
        // Danish word reads as a name it is not.
        precondition(
            InterlinearBridgePresentation.matchingCase(
                of: "Allocation",
                to: "tildele"
            ) == "allocation"
        )
        precondition(
            InterlinearBridgePresentation.matchingCase(
                of: "Copenhagen",
                to: "København"
            ) == "Copenhagen"
        )
        precondition(
            InterlinearBridgePresentation.matchingCase(
                of: "condition",
                to: "betingelse"
            ) == "condition"
        )
        precondition(
            InterlinearBridgePresentation.matchingCase(
                of: "CPR",
                to: "cpr"
            ) == "cPR",
            "Only the first letter follows the Danish; an acronym's remaining "
                + "capitals are not the translator's sentence case."
        )
        let cased = InterlinearBridgePresentation.units(
            text: "at CPR-kontoret kan tildele Allocation.",
            englishTokenIndexes: [4]
        )
        precondition(
            cased.last?.english == "allocation",
            "A gloss kept its sentence capital inside a line: "
                + String(describing: cased.last?.english)
        )
        precondition(cased.last?.danish == "tildele.")
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
