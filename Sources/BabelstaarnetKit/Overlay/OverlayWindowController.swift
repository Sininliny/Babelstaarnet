import AppKit
import BabelCore
import BabelLexicon
import SwiftUI

@MainActor
final class OverlayWindowController {
    private struct DisplayOverlay {
        var regions: [TextRegion]
        var screenFrame: CGRect
    }

    /// What the hover hit test reads. Two ticks that agree on all of it resolve
    /// to the same word, so the second one has nothing to do.
    private struct HoverInput: Equatable {
        let point: CGPoint
        let overlayGeneration: UInt64
        let interactionIsHeld: Bool
    }

    private let languages: LanguagePair
    private let dictionary: DictionaryService
    private let adaptiveExplanationService: AdaptiveExplanationService
    private let sentenceBridgeService: AdaptiveSentenceBridgeService
    private let sentenceAssembly: SentenceAssemblyPolicy
    private let passiveWordMeaningPolicy: PassiveWordMeaningPolicy
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
    /// What the reader last did to a word, and when. Read back whenever that
    /// word comes under the pointer again, so the tick is a fact about the word
    /// rather than a receipt for the keypress that has since scrolled away.
    private var rememberedActions:
        [String: (action: BridgeFeedbackConfirmation, at: Date)] = [:]
    private var pinnedByUser = false
    private var temporarilyHeldForIdle = false
    private var holdModifierPressed = false
    private var stationaryPoint: CGPoint?
    private var stationarySince: Date?
    /// Everything the hover answer is derived from, as of the last time it was
    /// derived. See `hoverNeedsUpdate(at:)`.
    private var lastHoverInput: HoverInput?
    /// Bumped whenever the page being hovered is replaced, which is the one
    /// input to the hit test that is not a value already at hand.
    private var overlayGeneration: UInt64 = 0
    private var autoSpeak = true
    private var hoverDelay = 0.7
    private var hotKeyConfiguration = HotKeyConfiguration.defaults
    private var bridgeConfiguration = LearningBridgeConfiguration.both
    private let onSpeakSourceWord: (String) -> Void
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
    private lazy var focusMarkerHostingView = NSHostingView(
        rootView: WordFocusMarkerView(state: bubbleState)
    )
    private lazy var wordBubblePanel = makeBubblePanel(
        contentView: wordBubbleHostingView
    )
    private lazy var sentenceBubblePanel = makeBubblePanel(
        contentView: sentenceBubbleHostingView
    )
    /// Unlike the panels, this one is laid over the page rather than beside it,
    /// so it must not take the click the reader meant for what is underneath.
    private lazy var focusMarkerPanel: NSPanel = {
        let panel = makeBubblePanel(
            contentView: focusMarkerHostingView,
            casts: false
        )
        panel.ignoresMouseEvents = true
        return panel
    }()

    init(
        languages: LanguagePair,
        learnerProfile: LearnerProfileStore,
        onSpeakSourceWord: @escaping (String) -> Void,
        onLearnerProfileChanged: @escaping (Bool) -> Void
    ) {
        self.languages = languages
        self.dictionary = DictionaryService(target: languages.target)
        self.adaptiveExplanationService = AdaptiveExplanationService(
            language: languages.source
        )
        self.sentenceBridgeService = AdaptiveSentenceBridgeService(
            language: languages.source
        )
        self.sentenceAssembly = SentenceAssemblyPolicy(
            language: languages.source
        )
        self.passiveWordMeaningPolicy = PassiveWordMeaningPolicy(
            language: languages.source,
            target: languages.target
        )
        self.learnerProfile = learnerProfile
        self.onSpeakSourceWord = onSpeakSourceWord
        self.onLearnerProfileChanged = onLearnerProfileChanged
        bubbleState.onKnown = { [weak self] in
            self?.markCurrentWordKnown()
        }
        bubbleState.onDontKnow = { [weak self] in
            self?.markCurrentWordUnknown()
        }
        bubbleState.onTogglePin = { [weak self] in
            self?.toggleBubblePin()
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

        overlays = Dictionary(grouping: regions, by: \.displayID)
            .compactMapValues { displayRegions in
                displayRegions.first.map {
                    DisplayOverlay(
                        regions: displayRegions,
                        screenFrame: $0.screenFrame
                    )
                }
            }
        overlayGeneration &+= 1

        // A scan that read nothing leaves nothing to hover. The pointer was
        // still being followed twenty times a second afterwards, measuring it
        // against a page with no words in it, for as long as the reader stayed
        // over the blank part of the screen.
        guard !overlays.isEmpty else {
            stopMouseTracking()
            dismissBubble()
            return
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
            if let replacement = HoverHitTesting.replacement(
                for: currentWord,
                in: regions
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
        overlayGeneration &+= 1
        dismissBubble()
        expandedEnglishWords.removeAll()
        stopMouseTracking()
        hoverSpeechTimer?.invalidate()
        hoverSpeechTimer = nil
    }

    var isHoldingInteraction: Bool {
        bubblesAreVisible && isBubbleHeld
    }

    /// - Parameter casts: Whether the panel is lifted off the page by a shadow.
    ///   The shadow has to be the window's own: a panel is sized to exactly the
    ///   bubble it carries, so a shadow drawn inside it has nowhere outside the
    ///   bubble to fall and is clipped at the panel's edge — which left it
    ///   pooling in the corner notches and reading as blurred corners. A window
    ///   shadow is drawn outside the window and is shaped from what the panel
    ///   actually paints, so it follows the rounded corners without being cut.
    ///   Off for the focus marker, which is a rule laid over the page rather
    ///   than a surface standing above it.
    private func makeBubblePanel(
        contentView: NSView,
        casts shadow: Bool = true
    ) -> NSPanel {
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
        panel.hasShadow = shadow
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
                guard let self else {
                    return
                }
                let point = NSEvent.mouseLocation
                self.updateHoldModifierState()
                self.updateStationaryHold(at: point)
                guard self.hoverNeedsUpdate(at: point) else {
                    return
                }
                self.updateHover(at: point)
            }
        }
        // Nothing here needs the tick to land on the millisecond, and a timer
        // the kernel is allowed to slide can be served alongside a wake-up it
        // was making anyway instead of forcing one of its own.
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func stopMouseTracking() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        lastHoverInput = nil
    }

    /// Whether this tick can resolve to anything the last one did not.
    ///
    /// Following the pointer is the whole hit test — every word on the page
    /// measured against it — and it runs twenty times a second for as long as a
    /// page is on screen. But reading is done with the pointer parked, so the
    /// common tick is one where none of what the test reads has moved since the
    /// last: same point, same page, same hold. Resolving that tick again cannot
    /// produce a different word, and now costs a comparison instead of a walk
    /// over the page.
    private func hoverNeedsUpdate(at point: CGPoint) -> Bool {
        HoverInput(
            point: point,
            overlayGeneration: overlayGeneration,
            interactionIsHeld: isBubbleHeld
        ) != lastHoverInput
    }

    private func updateHover(
        at point: CGPoint,
        force: Bool = false
    ) {
        // Recorded on the way out, so it describes the state the hover was
        // actually left in rather than the one it was entered with.
        defer {
            lastHoverInput = HoverInput(
                point: point,
                overlayGeneration: overlayGeneration,
                interactionIsHeld: isBubbleHeld
            )
        }

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
        }
        currentWord = match?.word
        currentRegion = match?.region

        if targetChanged {
            // Whatever was done to *this* word, if it was recent enough. A
            // different word carries its own answer, which is usually none.
            bubbleState.restoreFeedback(
                match.map { rememberedAction(for: $0.word.sourceText) } ?? nil
            )
        }

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
            sourceFrame: sentenceFrame(for: match.word, in: match.region)
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
                self?.onSpeakSourceWord(match.word.sourceText)
            }
        }
        RunLoop.main.add(speechTimer, forMode: .common)
        hoverSpeechTimer = speechTimer
    }

    private func hoverCard(
        for word: WordRegion,
        in region: TextRegion
    ) -> HoverCard {
        let key = learnerProfile.normalizedKey(for: word.sourceText)
        let expanded = expandedEnglishWords.contains(key)
        let now = Date()
        var knowledgeLevelCache: [String: Int] = [:]
        // Two doors onto one answer. Callers holding a raw token come in
        // through `knowledgeLevelForWord` and pay for the normalization;
        // callers that normalized the token in order to look at it — which is
        // every token of both bridges — hand the key straight over.
        let knowledgeLevelForKey: (String) -> Int = {
            [learnerProfile] key in
            if let cached = knowledgeLevelCache[key] {
                return cached
            }
            let level = learnerProfile.progress(
                forKey: key,
                at: now
            ).effectiveKnowledgeLevel(at: now)
            knowledgeLevelCache[key] = level
            return level
        }
        let knowledgeLevelForWord: (String) -> Int = {
            [learnerProfile] candidate in
            knowledgeLevelForKey(learnerProfile.normalizedKey(for: candidate))
        }
        let stateForWord: (String) -> LanguageTransferState = { candidate in
            LanguageTransferState.forKnowledgeLevel(
                knowledgeLevelForWord(candidate)
            )
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
        let wordKnowledgeLevel = knowledgeLevelForWord(word.sourceText)
        let wordEnglishMeaning = passiveWordMeaningPolicy.directMeaning(
            sourceWord: word.sourceText,
            translation: word.translatedText,
            knowledgeLevel: wordKnowledgeLevel
        )
        let explanation = adaptiveExplanationService.explanation(
            bridgeText: bridge?.text ?? fallbackBridge(for: word),
            englishMeaning: word.translatedText,
            expandedEnglish: expanded
                ? dictionary.adaptiveGloss(
                    for: word.translatedText,
                    sourceWord: word.sourceText
                )
                : "",
            expandEnglish: expanded
        )

        return HoverCard(
            word: word,
            wordKnowledgeLevel: wordKnowledgeLevel,
            wordEnglishMeaning: wordEnglishMeaning,
            wordBridgeText: wordBridge.text,
            wordBridgeEnglishTokenIndexes:
                wordBridge.englishTokenIndexes,
            wordBridgeKnowledgeLevels: tokenKnowledgeLevels(
                in: wordBridge.text,
                englishTokenIndexes: wordBridge.englishTokenIndexes,
                knowledgeLevelForKey: knowledgeLevelForKey
            ),
            learningText: explanation.primaryText,
            englishSupport: explanation.englishSupport,
            englishIsExpanded: explanation.englishIsExpanded,
            adaptiveEnglishTokenIndexes: bridge?.englishTokenIndexes ?? [],
            sentenceBridgeKnowledgeLevels: tokenKnowledgeLevels(
                in: explanation.primaryText,
                englishTokenIndexes: bridge?.englishTokenIndexes ?? [],
                knowledgeLevelForKey: knowledgeLevelForKey
            ),
            // Both the Danish the word kept and the English standing in for it
            // count as the word being pointed at: whichever of the two the
            // sentence ended up showing is the one the panel above is
            // answering about.
            sentenceFocusTokenIndexes: tokenIndexes(
                of: word.sourceText,
                in: explanation.primaryText,
                excluding: bridge?.englishTokenIndexes ?? []
            ) + (bridge?.focusEnglishTokenIndexes ?? []),
            sentencePanelStandsAlone:
                !bridgeConfiguration.showsWordBridge,
            speaksOnHover: autoSpeak,
            knownShortcutLabel: hotKeyConfiguration.known.displayText,
            dontKnowShortcutLabel: hotKeyConfiguration.dontKnow.displayText,
            pinShortcutLabel: hotKeyConfiguration.togglePin.displayText
        )
    }

    private func tokenKnowledgeLevels(
        in text: String,
        englishTokenIndexes: [Int],
        knowledgeLevelForKey: (String) -> Int
    ) -> [Int: Int] {
        let englishIndexes = Set(englishTokenIndexes)
        return Dictionary(
            uniqueKeysWithValues: text
                .split(whereSeparator: \Character.isWhitespace)
                .enumerated()
                .compactMap { index, token in
                    guard !englishIndexes.contains(index) else {
                        return nil
                    }
                    let word = learnerProfile.normalizedKey(
                        for: String(token)
                    )
                    guard !word.isEmpty else {
                        return nil
                    }
                    return (index, knowledgeLevelForKey(word))
                }
        )
    }

    private func tokenIndexes(
        of word: String,
        in text: String,
        excluding excludedIndexes: [Int]
    ) -> [Int] {
        let target = learnerProfile.normalizedKey(for: word)
        let excluded = Set(excludedIndexes)
        guard !target.isEmpty else {
            return []
        }
        return text
            .split(whereSeparator: \Character.isWhitespace)
            .enumerated()
            .compactMap { index, token in
                guard !excluded.contains(index),
                      learnerProfile.normalizedKey(
                        for: String(token)
                      ) == target else {
                    return nil
                }
                return index
            }
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

        // The direct EN row already supplies the safe focused meaning. When no
        // useful Danish explanation exists, an additional "Betyder …" line is
        // repetitive and can accidentally bypass the knowledge-level policy.
        return AdaptiveSentenceBridge(
            text: "",
            englishTokenIndexes: []
        )
    }

    /// What the bubbles must not cover: every line the sentence in the panel is
    /// printed on, rather than only the one under the pointer.
    ///
    /// A wrapped sentence is still being read on all of its lines, and the
    /// panel explaining it was landing on the rest of it — so the reader could
    /// have the bridge or the Danish it was bridging, but not both.
    private func sentenceFrame(
        for word: WordRegion,
        in region: TextRegion
    ) -> CGRect {
        sentenceAssembly.lines(
            containing: word,
            in: region,
            among: overlays[word.displayID]?.regions ?? [region]
        ).reduce(region.frame) { $0.union($1.frame) }
    }

    private func adaptiveSentenceBridge(
        for word: WordRegion,
        in region: TextRegion,
        stateForWord: (String) -> LanguageTransferState
    ) -> AdaptiveSentenceBridge? {
        // The sentence, not the line it wrapped on. Both the text and the
        // occurrence of the hovered word come back from the same assembly, so
        // a word repeated across the line break still resolves to the one
        // under the pointer.
        let sentence = sentenceAssembly.sentence(
            containing: word,
            in: region,
            among: overlays[word.displayID]?.regions ?? [region]
        )
        var translations: [String: String] = [:]
        for candidate in sentence.lines.flatMap(\.words) {
            translations[
                learnerProfile.normalizedKey(for: candidate.sourceText)
            ] = candidate.translatedText
        }
        let result = sentenceBridgeService.bridge(
            danishSentence: sentence.text,
            englishByDanishWord: translations,
            focusWord: word.sourceText,
            focusOccurrence: sentence.focusOccurrence,
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
        // `prepareBubbles` has already published the card in order to measure
        // it; publishing the same card again only redraws both bubbles twice.
        let sizes = prepareBubbles(card)
        showFocusMarker(under: word)

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
            place(
                wordBubblePanel,
                at: bubbleFrame(center: centers.word, size: sizes.word)
            )
            place(
                sentenceBubblePanel,
                at: bubbleFrame(center: centers.sentence, size: sizes.sentence)
            )

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
            place(
                wordBubblePanel,
                at: bubbleFrame(center: center, size: sizes.word)
            )

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
            place(
                sentenceBubblePanel,
                at: bubbleFrame(center: center, size: sizes.sentence)
            )

        case (false, false):
            hideBridgePanels()
            return
        }

        updateBubbleHotKeys()
    }

    private func showFocusMarker(under word: WordRegion) {
        place(focusMarkerPanel, at: WordFocusMarker.frame(under: word.frame))
    }

    /// No panel could be placed, so there is no answer for a mark to point at.
    private func hideBridgePanels() {
        wordBubblePanel.orderOut(nil)
        sentenceBubblePanel.orderOut(nil)
        focusMarkerPanel.orderOut(nil)
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

    /// Puts a panel on screen at a frame the display can actually draw sharply.
    private func place(_ panel: NSPanel, at frame: CGRect) {
        panel.setFrame(pixelAligned(frame), display: true)
        panel.orderFrontRegardless()
        // The shadow is shaped from what the panel paints and then cached, and
        // the panel paints a different answer for every word hovered. Asked for
        // after the panel is on screen rather than before, so it is shaped from
        // a bubble that has been drawn.
        if panel.hasShadow {
            panel.invalidateShadow()
        }
    }

    /// Word frames come from OCR, so they land on arbitrary fractions of a
    /// point, and so does a panel placed against one. A panel whose origin sits
    /// off the display's pixel grid has everything drawn in it resampled across
    /// two pixels — text included, but the corner arcs worst, since a curve
    /// crossing the grid at an angle has nothing but its antialiasing to
    /// describe it and half a pixel of offset smears that over twice the width.
    ///
    /// Snapping to the grid of the screen the panel is actually on, rather than
    /// to whole points, moves it by at most half a pixel: on a Retina display
    /// the grid is half-point, and rounding to points would throw away
    /// placement accuracy to no purpose. Sizes are left alone — they are whole
    /// numbers already, and rounding one would re-wrap the text inside it.
    private func pixelAligned(_ frame: CGRect) -> CGRect {
        let scale = NSScreen.screens.first { $0.frame.intersects(frame) }?
            .backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
        guard scale > 0 else {
            return frame
        }
        return CGRect(
            x: (frame.minX * scale).rounded() / scale,
            y: (frame.minY * scale).rounded() / scale,
            width: frame.width,
            height: frame.height
        )
    }

    private func markCurrentWordUnknown() {
        guard let currentWord else {
            return
        }
        let key = learnerProfile.normalizedKey(
            for: currentWord.sourceText
        )
        learnerProfile.recordUnknown(for: currentWord.sourceText)
        if expandedEnglishWords.count >= 256,
           !expandedEnglishWords.contains(key),
           let evictionCandidate = expandedEnglishWords.first {
            expandedEnglishWords.remove(evictionCandidate)
        }
        expandedEnglishWords.insert(key)
        onLearnerProfileChanged(true)
        remember(.englishRestored, for: currentWord.sourceText)
        refreshCurrentCard(preservePosition: true)
        bubbleState.showFeedback(.englishRestored)
    }

    private func markCurrentWordKnown() {
        guard let currentWord else {
            return
        }
        learnerProfile.recordKnown(for: currentWord.sourceText)
        expandedEnglishWords.remove(
            learnerProfile.normalizedKey(for: currentWord.sourceText)
        )
        onLearnerProfileChanged(true)
        remember(.markedKnown, for: currentWord.sourceText)
        refreshCurrentCard(preservePosition: true)
        bubbleState.showFeedback(.markedKnown)
    }

    private func remember(
        _ action: BridgeFeedbackConfirmation,
        for word: String
    ) {
        let key = learnerProfile.normalizedKey(for: word)
        let now = Date()
        // Drop what has aged out before adding, so the table stays the size of
        // a reading session rather than growing with one.
        rememberedActions = rememberedActions.filter {
            BridgeFeedbackMemory.isRemembered(recordedAt: $0.value.at, now: now)
        }
        if rememberedActions.count >= BridgeFeedbackMemory.capacity,
           rememberedActions[key] == nil,
           let oldest = rememberedActions.min(by: { $0.value.at < $1.value.at })
        {
            rememberedActions.removeValue(forKey: oldest.key)
        }
        rememberedActions[key] = (action, now)
    }

    private func rememberedAction(
        for word: String
    ) -> BridgeFeedbackConfirmation? {
        let key = learnerProfile.normalizedKey(for: word)
        guard let record = rememberedActions[key] else {
            return nil
        }
        guard BridgeFeedbackMemory.isRemembered(recordedAt: record.at) else {
            rememberedActions.removeValue(forKey: key)
            return nil
        }
        return record.action
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
            let sourceFrame = sentenceFrame(
                for: currentWord,
                in: currentRegion
            )
            // The word has not changed, but the panels are being ordered front
            // again and the mark belongs with them.
            showFocusMarker(under: currentWord)
            if bridgeConfiguration.showsWordBridge {
                let wordFrame = BubbleInteractionPolicy.preservedFrame(
                    oldFrame: wordBubblePanel.frame,
                    newSize: sizes.word,
                    screenFrame: currentWord.screenFrame,
                    anchoring: .growingAwayFrom(
                        sourceFrame: sourceFrame,
                        bubbleFrame: wordBubblePanel.frame
                    )
                )
                place(wordBubblePanel, at: wordFrame)
            } else {
                wordBubblePanel.orderOut(nil)
            }
            if bridgeConfiguration.showsSentenceBridge {
                let sentenceFrame = BubbleInteractionPolicy.preservedFrame(
                    oldFrame: sentenceBubblePanel.frame,
                    newSize: sizes.sentence,
                    screenFrame: currentWord.screenFrame,
                    anchoring: .growingAwayFrom(
                        sourceFrame: sourceFrame,
                        bubbleFrame: sentenceBubblePanel.frame
                    )
                )
                place(sentenceBubblePanel, at: sentenceFrame)
            } else {
                sentenceBubblePanel.orderOut(nil)
            }
            updateBubbleHotKeys()
        } else {
            showBubbles(
                card,
                near: currentWord,
                sourceFrame: sentenceFrame(
                    for: currentWord,
                    in: currentRegion
                )
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
           learnerProfile.normalizedKey(for: meaning)
            != learnerProfile.normalizedKey(for: word.sourceText) {
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
        focusMarkerPanel.orderOut(nil)
        bubbleHotKeyService.unregister()
        currentWord = nil
        currentRegion = nil
        hoverAnchorPoint = nil
        pinnedByUser = false
        temporarilyHeldForIdle = false
        holdModifierPressed = false
        stationaryPoint = nil
        stationarySince = nil
        bubbleState.setPinned(false)
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
        bubbleState.setPinned(pinnedByUser)
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
            bubbleState.setPinned(pinnedByUser)
            return
        }
        guard down != holdModifierPressed else {
            return
        }
        holdModifierPressed = down
        bubbleState.setPinned(pinnedByUser)
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

        if temporarilyHeldForIdle {
            if BubbleInteractionPolicy.shouldReleaseTemporaryHold(
                pointerMoved: pointerMoved,
                idleDuration: systemIdleMonitor.idleDuration()
            ) {
                temporarilyHeldForIdle = false
                stationaryPoint = point
                stationarySince = Date()
            }
            return
        }

        // A pointer that has moved settles the question on its own, and asking
        // the window server how long the session has been idle is the one call
        // in this tick that leaves the process.
        if pointerMoved || systemIdleMonitor.idleDuration() < 0.12 {
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
