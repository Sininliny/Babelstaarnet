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
    private let learnerProfile: LearnerProfileStore
    private let systemIdleMonitor = SystemIdleMonitor()
    private let bubbleState = OverlayState()
    private var overlays: [CGDirectDisplayID: DisplayOverlay] = [:]
    private var mouseTimer: Timer?
    private var hoverSpeechTimer: Timer?
    private var currentWord: WordRegion?
    private var hoverAnchorPoint: CGPoint?
    private var expandedEnglishWords = Set<String>()
    private var pinnedByUser = false
    private var temporarilyHeldForIdle = false
    private var optionHeld = false
    private var stationaryPoint: CGPoint?
    private var stationarySince: Date?
    private var autoSpeak = true
    private var hoverDelay = 0.7
    private var translationMode: TranslationMode = .english
    private var explanationMode: ExplanationMode = .english
    private let onSpeakDanish: (String) -> Void
    private let onLearnerProfileChanged: () -> Void
    private lazy var bubbleHotKeyService = BubbleHotKeyService {
        [weak self] action in
        self?.performBubbleAction(action)
    }
    private lazy var bubbleHostingView = NSHostingView(
        rootView: OverlayRootView(state: bubbleState)
    )
    private lazy var bubblePanel = makeBubblePanel()

    init(
        learnerProfile: LearnerProfileStore,
        onSpeakDanish: @escaping (String) -> Void,
        onLearnerProfileChanged: @escaping () -> Void
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
        translationMode: TranslationMode,
        explanationMode: ExplanationMode
    ) {
        self.autoSpeak = autoSpeak
        self.hoverDelay = hoverDelay
        self.translationMode = translationMode
        self.explanationMode = explanationMode

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
        if bubblePanel.isVisible, let currentWord {
            let candidates = overlays.values.flatMap { $0.regions }
                .flatMap(\.words)
            if let replacement = HoverHitTesting.replacement(
                for: currentWord,
                in: candidates
            ) {
                self.currentWord = replacement
                refreshCurrentCard(preservePosition: true)
            }
            if isBubbleHeld || BubbleInteractionPolicy.pointerIsStationary(
                pointer,
                since: hoverAnchorPoint
            ) {
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
        bubblePanel.isVisible && isBubbleHeld
    }

    private func makeBubblePanel() -> NSPanel {
        bubbleHostingView.wantsLayer = true
        bubbleHostingView.layer?.backgroundColor = NSColor.clear.cgColor

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
        panel.contentView = bubbleHostingView
        return panel
    }

    private func startMouseTracking() {
        guard mouseTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                let point = NSEvent.mouseLocation
                self?.updateOptionHoldState()
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
        if !force, isBubbleHeld, bubblePanel.isVisible {
            return
        }

        var match: (overlay: DisplayOverlay, word: WordRegion)?
        for overlay in overlays.values
        where overlay.screenFrame.contains(point) {
            if let word = HoverHitTesting.word(
                at: point,
                in: overlay.regions,
                retaining: currentWord
            ) {
                match = (overlay, word)
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
        guard targetChanged || force else {
            return
        }

        if targetChanged {
            hoverSpeechTimer?.invalidate()
            hoverSpeechTimer = nil
        }
        currentWord = match?.word

        guard let match else {
            dismissBubble()
            return
        }

        hoverAnchorPoint = point
        stationaryPoint = point
        stationarySince = Date()
        temporarilyHeldForIdle = false
        bubbleState.isStationaryHeld = false

        if targetChanged, explanationMode == .adaptive {
            learnerProfile.recordEncounter(for: match.word.sourceText)
            onLearnerProfileChanged()
        }

        let card = hoverCard(for: match.word)
        showBubble(
            card,
            near: match.word,
            obstacles: sourceFrames(for: match.word)
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
            Task { @MainActor in
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

    private func hoverCard(for word: WordRegion) -> HoverCard {
        let definition: String
        var englishSupport: String?
        var familiarityLabel: String?
        var englishIsExpanded = false

        switch explanationMode {
        case .adaptive:
            let key = LearnerProfileStore.normalizedKey(
                for: word.sourceText
            )
            let expanded = expandedEnglishWords.contains(key)
            let mixed = word.adaptiveExplanation.isEmpty
                ? fallbackMixedExplanation(for: word)
                : word.adaptiveExplanation
            let explanation = adaptiveExplanationService.explanation(
                easyDanish: mixed,
                englishMeaning: word.translatedText,
                shortEnglish: "Means “\(word.translatedText)”.",
                fullEnglish: expanded
                    ? dictionary.adaptiveEnglishGloss(
                        for: word.translatedText,
                        sourceWord: word.sourceText
                    )
                    : "",
                progress: learnerProfile.progress(for: word.sourceText),
                expandEnglish: expanded
            )
            definition = explanation.primaryText
            englishSupport = explanation.englishSupport
            familiarityLabel = explanation.familiarityLabel
            englishIsExpanded = explanation.englishIsExpanded
        case .beginner:
            definition = dictionary.beginnerExplanation(
                for: word.translatedText,
                sourceWord: word.sourceText
            )
        case .english:
            definition = dictionary.definition(
                for: word.translatedText,
                sourceWord: word.sourceText
            )
        case .easyDanish:
            definition = word.beginnerExplanation.isEmpty
                ? "Ingen kort dansk forklaring fundet."
                : word.beginnerExplanation
        case .none:
            definition = ""
        }

        return HoverCard(
            word: word,
            definition: definition,
            englishSupport: englishSupport,
            familiarityLabel: familiarityLabel,
            englishIsExpanded: englishIsExpanded,
            translationMode: translationMode,
            explanationMode: explanationMode
        )
    }

    private func showBubble(
        _ card: HoverCard,
        near word: WordRegion,
        obstacles: [CGRect]
    ) {
        let size = prepareBubble(card)
        guard let center = OverlayLayout.hoverCenter(
            wordFrame: word.frame,
            estimatedSize: size,
            screenFrame: word.screenFrame,
            obstacles: obstacles
        ) else {
            bubbleState.hoverCard = nil
            bubblePanel.orderOut(nil)
            return
        }
        bubbleState.hoverCard = card
        bubblePanel.setFrame(
            CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: true
        )
        bubblePanel.orderFrontRegardless()
        updateBubbleHotKeys()
    }

    private func sourceFrames(for word: WordRegion) -> [CGRect] {
        for overlay in overlays.values {
            if let line = overlay.regions.first(where: {
                $0.words.contains(where: { $0.id == word.id })
            }) {
                return [line.frame]
            }
        }
        return [word.frame]
    }

    private func markCurrentWordUnknown() {
        guard let currentWord,
              explanationMode == .adaptive else {
            return
        }
        let key = LearnerProfileStore.normalizedKey(
            for: currentWord.sourceText
        )
        guard !expandedEnglishWords.contains(key) else {
            return
        }
        learnerProfile.recordUnknown(for: currentWord.sourceText)
        expandedEnglishWords.insert(key)
        onLearnerProfileChanged()
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
        onLearnerProfileChanged()
        refreshCurrentCard(preservePosition: true)
    }

    private func refreshCurrentCard(preservePosition: Bool) {
        guard let currentWord else {
            return
        }
        let replacement = overlays.values
            .compactMap {
                HoverHitTesting.replacement(
                    for: currentWord,
                    in: $0.regions.flatMap(\.words)
                )
            }
            .first ?? currentWord
        self.currentWord = replacement
        let card = hoverCard(for: replacement)
        if preservePosition, bubblePanel.isVisible {
            let size = prepareBubble(card)
            let frame = BubbleInteractionPolicy.preservedFrame(
                oldFrame: bubblePanel.frame,
                newSize: size,
                screenFrame: replacement.screenFrame
            )
            bubblePanel.setFrame(frame, display: true)
            bubblePanel.orderFrontRegardless()
            updateBubbleHotKeys()
        } else {
            showBubble(
                card,
                near: replacement,
                obstacles: sourceFrames(for: replacement)
            )
        }
    }

    private var isBubbleHeld: Bool {
        pinnedByUser || temporarilyHeldForIdle || optionHeld
    }

    private func fallbackMixedExplanation(for word: WordRegion) -> String {
        let meaning = word.translatedText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !word.beginnerExplanation.isEmpty, !meaning.isEmpty {
            return "\(word.sourceText) = \(meaning). \(word.beginnerExplanation)"
        }
        if !meaning.isEmpty {
            return "\(word.sourceText) = \(meaning)."
        }
        return word.beginnerExplanation
    }

    private func prepareBubble(_ card: HoverCard) -> CGSize {
        bubbleState.hoverCard = card
        bubbleHostingView.rootView = OverlayRootView(state: bubbleState)
        bubbleHostingView.invalidateIntrinsicContentSize()
        bubbleHostingView.layoutSubtreeIfNeeded()
        return HoverBubbleMetrics.fittedSize(bubbleHostingView.fittingSize)
    }

    private func dismissBubble() {
        bubbleState.hoverCard = nil
        bubblePanel.orderOut(nil)
        bubbleHotKeyService.unregister()
        currentWord = nil
        hoverAnchorPoint = nil
        pinnedByUser = false
        temporarilyHeldForIdle = false
        optionHeld = false
        stationaryPoint = nil
        stationarySince = nil
        bubbleState.isPinned = false
        bubbleState.isStationaryHeld = false
        bubbleState.isOptionHeld = false
    }

    private func updateBubbleHotKeys() {
        if bubblePanel.isVisible,
           currentWord != nil,
           explanationMode == .adaptive {
            bubbleHotKeyService.register()
        } else {
            bubbleHotKeyService.unregister()
        }
    }

    private func performBubbleAction(_ action: BubbleHotKeyAction) {
        guard bubblePanel.isVisible,
              currentWord != nil,
              explanationMode == .adaptive else {
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
        guard bubblePanel.isVisible else {
            return
        }
        if pinnedByUser {
            pinnedByUser = false
            stationaryPoint = NSEvent.mouseLocation
            stationarySince = Date()
        } else {
            pinnedByUser = true
            temporarilyHeldForIdle = false
            bubbleState.isStationaryHeld = false
        }
        bubbleState.isPinned = pinnedByUser
        refreshCurrentCard(preservePosition: true)
        if !isBubbleHeld {
            updateHover(at: NSEvent.mouseLocation)
        }
    }

    private func updateOptionHoldState() {
        let down = CGEventSource.flagsState(.combinedSessionState)
            .contains(.maskAlternate)
        guard bubblePanel.isVisible else {
            optionHeld = false
            bubbleState.isOptionHeld = false
            bubbleState.isPinned = pinnedByUser
            return
        }
        guard down != optionHeld else {
            return
        }
        optionHeld = down
        bubbleState.isOptionHeld = down
        bubbleState.isPinned = pinnedByUser
        refreshCurrentCard(preservePosition: true)
        if !down, !pinnedByUser {
            updateHover(at: NSEvent.mouseLocation)
        }
    }

    private func updateStationaryHold(at point: CGPoint) {
        guard bubblePanel.isVisible,
              let currentWord,
              !pinnedByUser,
              !optionHeld else {
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
                bubbleState.isStationaryHeld = false
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
        bubbleState.isStationaryHeld = true
        refreshCurrentCard(preservePosition: true)
    }
}
