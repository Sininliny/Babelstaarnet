import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private struct DisplayOverlay {
        var regions: [TextRegion]
        var screenFrame: CGRect
    }

    private let dictionary = DictionaryService()
    private let adaptiveExplanationService = AdaptiveExplanationService()
    private let sentenceBridgeService = AdaptiveSentenceBridgeService()
    private let learnerProfile: LearnerProfileStore
    private let systemIdleMonitor = SystemIdleMonitor()
    private let bubbleState = OverlayState()
    private var overlays: [CGDirectDisplayID: DisplayOverlay] = [:]
    private var mouseTimer: Timer?
    private var hoverSpeechTimer: Timer?
    private var currentWord: WordRegion?
    private var currentRegion: TextRegion?
    private var hoverAnchorPoint: CGPoint?
    private var expandedEnglishWords = Set<String>()
    private var pinnedByUser = false
    private var temporarilyHeldForIdle = false
    private var holdModifierPressed = false
    private var stationaryPoint: CGPoint?
    private var stationarySince: Date?
    private var autoSpeak = true
    private var hoverDelay = 0.7
    private var hotKeyConfiguration = HotKeyConfiguration.defaults
    private var bridgeConfiguration = LearningBridgeConfiguration.both
    private let onSpeakDanish: (String) -> Void
    private let onLearnerProfileChanged: (Bool) -> Void
    private lazy var bubbleHotKeyService = BubbleHotKeyService {
        [weak self] action in
        self?.performBubbleAction(action)
    }
    private lazy var wordBubbleHostingView = NSHostingView(
        rootView: WordBubbleView(state: bubbleState)
    )
    private lazy var sentenceBubbleHostingView = NSHostingView(
        rootView: SentenceBridgeBubbleView(state: bubbleState)
    )
    private lazy var wordBubblePanel = makeBubblePanel(
        contentView: wordBubbleHostingView
    )
    private lazy var sentenceBubblePanel = makeBubblePanel(
        contentView: sentenceBubbleHostingView
    )

    init(
        learnerProfile: LearnerProfileStore,
        onSpeakDanish: @escaping (String) -> Void,
        onLearnerProfileChanged: @escaping (Bool) -> Void
    ) {
        self.learnerProfile = learnerProfile
        self.onSpeakDanish = onSpeakDanish
        self.onLearnerProfileChanged = onLearnerProfileChanged
        bubbleState.onKnown = { [weak self] in
            self?.markCurrentWordKnown()
        }
        bubbleState.onDontKnow = { [weak self] in
            self?.markCurrentWordUnknown()
        }
    }

    func show(
        regions: [TextRegion],
        autoSpeak: Bool,
        hoverDelay: Double,
        hotKeyConfiguration: HotKeyConfiguration,
        bridgeConfiguration: LearningBridgeConfiguration
    ) {
        let presentationChanged = self.hotKeyConfiguration
            != hotKeyConfiguration
            || self.bridgeConfiguration != bridgeConfiguration
        self.autoSpeak = autoSpeak
        self.hoverDelay = hoverDelay
        self.hotKeyConfiguration = hotKeyConfiguration
        self.bridgeConfiguration = bridgeConfiguration

        let grouped = Dictionary(grouping: regions, by: \.displayID)
        let activeDisplayIDs = Set(grouped.keys)
        overlays = overlays.filter { activeDisplayIDs.contains($0.key) }

        for (displayID, displayRegions) in grouped {
            guard let screenFrame = displayRegions.first?.screenFrame else {
                continue
            }
            overlays[displayID] = DisplayOverlay(
                regions: displayRegions,
                screenFrame: screenFrame
            )
        }

        startMouseTracking()
        let pointer = NSEvent.mouseLocation
        if presentationChanged,
           currentWord != nil,
           currentRegion != nil {
            refreshCurrentCard(preservePosition: false)
            return
        }
        if bubblesAreVisible, let currentWord {
            if BubbleInteractionPolicy.shouldKeepLearningSnapshot(
                pointer: pointer,
                anchor: hoverAnchorPoint,
                interactionIsHeld: isBubbleHeld
            ) {
                return
            }

            let regions = overlays.values.flatMap(\.regions)
            let candidates = regions.flatMap(\.words)
            if let replacement = HoverHitTesting.replacement(
                for: currentWord,
                in: candidates
            ), let replacementRegion = region(
                containing: replacement,
                in: regions
            ) {
                self.currentWord = replacement
                currentRegion = replacementRegion
                hoverAnchorPoint = pointer
                refreshCurrentCard(preservePosition: true)
                return
            }
        }
        updateHover(at: pointer, force: currentWord == nil)
    }

    func hide() {
        overlays.removeAll()
        dismissBubble()
        expandedEnglishWords.removeAll()
        mouseTimer?.invalidate()
        mouseTimer = nil
        hoverSpeechTimer?.invalidate()
        hoverSpeechTimer = nil
    }

    var isHoldingInteraction: Bool {
        bubblesAreVisible && isBubbleHeld
    }

    private func makeBubblePanel(contentView: NSView) -> NSPanel {
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.contentView = contentView
        return panel
    }

    private func startMouseTracking() {
        guard mouseTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                let point = NSEvent.mouseLocation
                self?.updateHoldModifierState()
                self?.updateStationaryHold(at: point)
                self?.updateHover(at: point)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func updateHover(
        at point: CGPoint,
        force: Bool = false
    ) {
        if !force, isBubbleHeld, bubblesAreVisible {
            return
        }

        var match: (region: TextRegion, word: WordRegion)?
        for overlay in overlays.values
        where overlay.screenFrame.contains(point) {
            if let word = HoverHitTesting.word(
                at: point,
                in: overlay.regions,
                retaining: currentWord
            ), let matchedRegion = region(
                containing: word,
                in: overlay.regions
            ) {
                match = (matchedRegion, word)
                break
            }
        }

        if !force,
           match == nil,
           let currentWord,
           currentWord.frame.insetBy(dx: -18, dy: -18).contains(point) {
            return
        }

        let targetChanged = !HoverHitTesting.representsSameTarget(
            currentWord,
            match?.word
        )
        if !targetChanged,
           !BubbleInteractionPolicy.pointerIsStationary(
            point,
            since: hoverAnchorPoint
           ) {
            hoverAnchorPoint = point
        }
        guard targetChanged || force else {
            return
        }

        if targetChanged {
            hoverSpeechTimer?.invalidate()
            hoverSpeechTimer = nil
            bubbleState.clearFeedback()
        }
        currentWord = match?.word
        currentRegion = match?.region

        guard let match else {
            dismissBubble()
            return
        }

        hoverAnchorPoint = point
        stationaryPoint = point
        stationarySince = Date()
        temporarilyHeldForIdle = false

        if targetChanged {
            if learnerProfile.recordEncounter(
                for: match.word.sourceText,
                context: match.region.sourceText
            ) {
                onLearnerProfileChanged(false)
            }
        }

        let card = hoverCard(
            for: match.word,
            in: match.region
        )
        showBubbles(
            card,
            near: match.word,
            sourceFrame: match.region.frame
        )

        guard targetChanged,
              autoSpeak,
              !match.word.sourceText.isEmpty else {
            return
        }
        let speechTimer = Timer(
            timeInterval: hoverDelay,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard HoverHitTesting.representsSameTarget(
                    self?.currentWord,
                    match.word
                ) else {
                    return
                }
                self?.onSpeakDanish(match.word.sourceText)
            }
        }
        RunLoop.main.add(speechTimer, forMode: .common)
        hoverSpeechTimer = speechTimer
    }

    private func hoverCard(
        for word: WordRegion,
        in region: TextRegion
    ) -> HoverCard {
        let key = LearnerProfileStore.normalizedKey(for: word.sourceText)
        let expanded = expandedEnglishWords.contains(key)
        let now = Date()
        var transferStateCache: [String: LanguageTransferState] = [:]
        let stateForWord: (String) -> LanguageTransferState = {
            [learnerProfile] candidate in
            let normalized = LearnerProfileStore.normalizedKey(for: candidate)
            if let cached = transferStateCache[normalized] {
                return cached
            }
            let level = learnerProfile.progress(
                for: normalized,
                at: now
            ).effectiveKnowledgeLevel(at: now)
            let state = LanguageTransferState.forKnowledgeLevel(level)
            transferStateCache[normalized] = state
            return state
        }
        let bridge = adaptiveSentenceBridge(
            for: word,
            in: region,
            stateForWord: stateForWord
        )
        let wordBridge = adaptiveWordBridge(
            for: word,
            stateForWord: stateForWord
        )
        let explanation = adaptiveExplanationService.explanation(
            bridgeText: bridge?.text ?? fallbackBridge(for: word),
            englishMeaning: word.translatedText,
            expandedEnglish: expanded
                ? dictionary.adaptiveEnglishGloss(
                    for: word.translatedText,
                    sourceWord: word.sourceText
                )
                : "",
            expandEnglish: expanded
        )

        return HoverCard(
            word: word,
            wordBridgeText: wordBridge.text,
            wordBridgeEnglishTokenIndexes:
                wordBridge.englishTokenIndexes,
            learningText: explanation.primaryText,
            englishSupport: explanation.englishSupport,
            englishIsExpanded: explanation.englishIsExpanded,
            adaptiveEnglishTokenIndexes: bridge?.englishTokenIndexes ?? [],
            showsControlsInWordBridge:
                bridgeConfiguration.showsWordBridge,
            showsControlsInSentenceBridge:
                !bridgeConfiguration.showsWordBridge
                    && bridgeConfiguration.showsSentenceBridge,
            showsEnglishSupportInSentenceBridge:
                !bridgeConfiguration.showsWordBridge,
            knownShortcutLabel: hotKeyConfiguration.known.displayText,
            dontKnowShortcutLabel: hotKeyConfiguration.dontKnow.displayText,
            pinShortcutLabel: hotKeyConfiguration.togglePin.displayText
        )
    }

    private func adaptiveWordBridge(
        for word: WordRegion,
        stateForWord: (String) -> LanguageTransferState
    ) -> AdaptiveSentenceBridge {
        if !word.wordBridgeDanishText.isEmpty {
            return sentenceBridgeService.bridge(
                danishSentence: word.wordBridgeDanishText,
                englishByDanishWord: word.wordBridgeTranslations,
                focusWord: "",
                stateForWord: stateForWord
            )
        }
        if !word.wordBridgeText.isEmpty {
            return AdaptiveSentenceBridge(
                text: word.wordBridgeText,
                englishTokenIndexes:
                    word.wordBridgeEnglishTokenIndexes
            )
        }

        let meaning = word.translatedText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !meaning.isEmpty,
              LearnerProfileStore.normalizedKey(for: meaning)
                != LearnerProfileStore.normalizedKey(
                    for: word.sourceText
                ) else {
            return AdaptiveSentenceBridge(
                text: "Ingen lokal ordforklaring fundet.",
                englishTokenIndexes: []
            )
        }
        let text = "Betyder \(meaning)."
        let tokenCount = text.split(
            whereSeparator: \Character.isWhitespace
        ).count
        return AdaptiveSentenceBridge(
            text: text,
            englishTokenIndexes: Array(1..<tokenCount)
        )
    }

    private func adaptiveSentenceBridge(
        for word: WordRegion,
        in region: TextRegion,
        stateForWord: (String) -> LanguageTransferState
    ) -> AdaptiveSentenceBridge? {
        var translations: [String: String] = [:]
        for candidate in region.words {
            translations[
                LearnerProfileStore.normalizedKey(for: candidate.sourceText)
            ] = candidate.translatedText
        }
        let focusKey = LearnerProfileStore.normalizedKey(for: word.sourceText)
        let focusIndex = region.words.firstIndex(where: { $0.id == word.id })
            ?? 0
        let focusOccurrence = region.words[..<focusIndex].filter {
            LearnerProfileStore.normalizedKey(for: $0.sourceText) == focusKey
        }.count
        let result = sentenceBridgeService.bridge(
            danishSentence: region.sourceText,
            englishByDanishWord: translations,
            focusWord: word.sourceText,
            focusOccurrence: focusOccurrence,
            stateForWord: stateForWord
        )
        guard !result.text.isEmpty else {
            return nil
        }
        return result
    }

    private func showBubbles(
        _ card: HoverCard,
        near word: WordRegion,
        sourceFrame: CGRect
    ) {
        let sizes = prepareBubbles(card)
        bubbleState.hoverCard = card

        switch (
            bridgeConfiguration.showsWordBridge,
            bridgeConfiguration.showsSentenceBridge
        ) {
        case (true, true):
            guard let centers = OverlayLayout.learningBubbleCenters(
                wordFrame: word.frame,
                sourceFrame: sourceFrame,
                wordSize: sizes.word,
                sentenceSize: sizes.sentence,
                screenFrame: word.screenFrame
            ) else {
                hideBridgePanels()
                return
            }
            wordBubblePanel.setFrame(
                bubbleFrame(center: centers.word, size: sizes.word),
                display: true
            )
            sentenceBubblePanel.setFrame(
                bubbleFrame(center: centers.sentence, size: sizes.sentence),
                display: true
            )
            wordBubblePanel.orderFrontRegardless()
            sentenceBubblePanel.orderFrontRegardless()

        case (true, false):
            guard let center = OverlayLayout.hoverCenter(
                wordFrame: word.frame,
                estimatedSize: sizes.word,
                screenFrame: word.screenFrame,
                obstacles: [sourceFrame]
            ) else {
                hideBridgePanels()
                return
            }
            sentenceBubblePanel.orderOut(nil)
            wordBubblePanel.setFrame(
                bubbleFrame(center: center, size: sizes.word),
                display: true
            )
            wordBubblePanel.orderFrontRegardless()

        case (false, true):
            guard let center = OverlayLayout.translationCenter(
                sourceFrame: sourceFrame,
                estimatedSize: sizes.sentence,
                screenFrame: word.screenFrame,
                obstacles: [sourceFrame]
            ) ?? OverlayLayout.hoverCenter(
                wordFrame: word.frame,
                estimatedSize: sizes.sentence,
                screenFrame: word.screenFrame,
                obstacles: [sourceFrame]
            ) else {
                hideBridgePanels()
                return
            }
            wordBubblePanel.orderOut(nil)
            sentenceBubblePanel.setFrame(
                bubbleFrame(center: center, size: sizes.sentence),
                display: true
            )
            sentenceBubblePanel.orderFrontRegardless()

        case (false, false):
            hideBridgePanels()
            return
        }

        updateBubbleHotKeys()
    }

    private func hideBridgePanels() {
            wordBubblePanel.orderOut(nil)
            sentenceBubblePanel.orderOut(nil)
        bubbleHotKeyService.unregister()
    }

    private func bubbleFrame(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func markCurrentWordUnknown() {
        guard let currentWord else {
            return
        }
        let key = LearnerProfileStore.normalizedKey(
            for: currentWord.sourceText
        )
        learnerProfile.recordUnknown(for: currentWord.sourceText)
        if expandedEnglishWords.count >= 256,
           !expandedEnglishWords.contains(key),
           let evictionCandidate = expandedEnglishWords.first {
            expandedEnglishWords.remove(evictionCandidate)
        }
        expandedEnglishWords.insert(key)
        bubbleState.showFeedback(.englishRestored)
        onLearnerProfileChanged(true)
        refreshCurrentCard(preservePosition: true)
    }

    private func markCurrentWordKnown() {
        guard let currentWord else {
            return
        }
        learnerProfile.recordKnown(for: currentWord.sourceText)
        expandedEnglishWords.remove(
            LearnerProfileStore.normalizedKey(for: currentWord.sourceText)
        )
        bubbleState.showFeedback(.markedKnown)
        onLearnerProfileChanged(true)
        refreshCurrentCard(preservePosition: true)
    }

    private func refreshCurrentCard(preservePosition: Bool) {
        guard let currentWord,
              let currentRegion else {
            return
        }
        let card = hoverCard(
            for: currentWord,
            in: currentRegion
        )
        if preservePosition, bubblesAreVisible {
            let sizes = prepareBubbles(card)
            if bridgeConfiguration.showsWordBridge {
                let wordFrame = BubbleInteractionPolicy.preservedFrame(
                    oldFrame: wordBubblePanel.frame,
                    newSize: sizes.word,
                    screenFrame: currentWord.screenFrame
                )
                wordBubblePanel.setFrame(wordFrame, display: true)
                wordBubblePanel.orderFrontRegardless()
            } else {
                wordBubblePanel.orderOut(nil)
            }
            if bridgeConfiguration.showsSentenceBridge {
                let sentenceFrame = BubbleInteractionPolicy.preservedFrame(
                    oldFrame: sentenceBubblePanel.frame,
                    newSize: sizes.sentence,
                    screenFrame: currentWord.screenFrame
                )
                sentenceBubblePanel.setFrame(sentenceFrame, display: true)
                sentenceBubblePanel.orderFrontRegardless()
            } else {
                sentenceBubblePanel.orderOut(nil)
            }
            updateBubbleHotKeys()
        } else {
            showBubbles(
                card,
                near: currentWord,
                sourceFrame: currentRegion.frame
            )
        }
    }

    private var isBubbleHeld: Bool {
        pinnedByUser || temporarilyHeldForIdle || holdModifierPressed
    }

    private var bubblesAreVisible: Bool {
        wordBubblePanel.isVisible || sentenceBubblePanel.isVisible
    }

    private func region(
        containing word: WordRegion,
        in regions: [TextRegion]
    ) -> TextRegion? {
        regions.first { region in
            region.words.contains { $0.id == word.id }
        } ?? regions.first { region in
            region.words.contains {
                HoverHitTesting.representsSameTarget($0, word)
            }
        }
    }

    private func fallbackBridge(for word: WordRegion) -> String {
        let meaning = word.translatedText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !meaning.isEmpty,
           LearnerProfileStore.normalizedKey(for: meaning)
            != LearnerProfileStore.normalizedKey(for: word.sourceText) {
            return "\(word.sourceText) = \(meaning)."
        }
        return word.sourceText
    }

    private func prepareBubbles(
        _ card: HoverCard
    ) -> (word: CGSize, sentence: CGSize) {
        bubbleState.hoverCard = card
        var wordSize = CGSize.zero
        var sentenceSize = CGSize.zero
        if bridgeConfiguration.showsWordBridge {
            wordBubbleHostingView.rootView = WordBubbleView(state: bubbleState)
            wordBubbleHostingView.invalidateIntrinsicContentSize()
            wordBubbleHostingView.layoutSubtreeIfNeeded()
            wordSize = WordBubbleMetrics.fittedSize(
                wordBubbleHostingView.fittingSize
            )
        }
        if bridgeConfiguration.showsSentenceBridge {
            sentenceBubbleHostingView.rootView = SentenceBridgeBubbleView(
                state: bubbleState
            )
            sentenceBubbleHostingView.invalidateIntrinsicContentSize()
            sentenceBubbleHostingView.layoutSubtreeIfNeeded()
            sentenceSize = SentenceBubbleMetrics.fittedSize(
                sentenceBubbleHostingView.fittingSize
            )
        }
        return (wordSize, sentenceSize)
    }

    private func dismissBubble() {
        bubbleState.clearFeedback()
        bubbleState.hoverCard = nil
        wordBubblePanel.orderOut(nil)
        sentenceBubblePanel.orderOut(nil)
        bubbleHotKeyService.unregister()
        currentWord = nil
        currentRegion = nil
        hoverAnchorPoint = nil
        pinnedByUser = false
        temporarilyHeldForIdle = false
        holdModifierPressed = false
        stationaryPoint = nil
        stationarySince = nil
        bubbleState.isPinned = false
    }

    private func updateBubbleHotKeys() {
        if bubblesAreVisible,
           currentWord != nil {
            bubbleHotKeyService.register(
                configuration: hotKeyConfiguration
            )
        } else {
            bubbleHotKeyService.unregister()
        }
    }

    private func performBubbleAction(_ action: BubbleHotKeyAction) {
        guard bubblesAreVisible,
              currentWord != nil else {
            return
        }
        switch action {
        case .known:
            markCurrentWordKnown()
        case .dontKnow:
            markCurrentWordUnknown()
        case .togglePin:
            toggleBubblePin()
        }
    }

    private func toggleBubblePin() {
        guard bubblesAreVisible else {
            return
        }
        if pinnedByUser {
            pinnedByUser = false
            stationaryPoint = NSEvent.mouseLocation
            stationarySince = Date()
        } else {
            pinnedByUser = true
            temporarilyHeldForIdle = false
        }
        bubbleState.isPinned = pinnedByUser
        refreshCurrentCard(preservePosition: true)
        if !isBubbleHeld {
            updateHover(at: NSEvent.mouseLocation)
        }
    }

    private func updateHoldModifierState() {
        let down = hotKeyConfiguration.holdModifier.isPressed(
            in: CGEventSource.flagsState(.combinedSessionState)
        )
        guard bubblesAreVisible else {
            holdModifierPressed = false
            bubbleState.isPinned = pinnedByUser
            return
        }
        guard down != holdModifierPressed else {
            return
        }
        holdModifierPressed = down
        bubbleState.isPinned = pinnedByUser
        if !down, !pinnedByUser {
            updateHover(at: NSEvent.mouseLocation)
        }
    }

    private func updateStationaryHold(at point: CGPoint) {
        guard bubblesAreVisible,
              let currentWord,
              !pinnedByUser,
              !holdModifierPressed else {
            return
        }

        let pointerMoved = !BubbleInteractionPolicy.pointerIsStationary(
            point,
            since: stationaryPoint
        )
        let idleDuration = systemIdleMonitor.idleDuration()
        let receivedInput = idleDuration < 0.12

        if temporarilyHeldForIdle {
            if BubbleInteractionPolicy.shouldReleaseTemporaryHold(
                pointerMoved: pointerMoved,
                idleDuration: idleDuration
            ) {
                temporarilyHeldForIdle = false
                stationaryPoint = point
                stationarySince = Date()
            }
            return
        }

        if pointerMoved || receivedInput {
            stationaryPoint = point
            stationarySince = Date()
            return
        }

        guard let stationarySince,
              BubbleInteractionPolicy.shouldPinAfterStationaryHover(
                point: point,
                anchor: stationaryPoint,
                elapsed: Date().timeIntervalSince(stationarySince),
                sourceFrame: currentWord.frame
              ) else {
            return
        }

        temporarilyHeldForIdle = true
    }
}
