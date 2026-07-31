import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayState: ObservableObject {
    @Published var regions: [TextRegion] = []
    @Published var hoverCard: HoverCard?
    @Published var screenFrame: CGRect = .zero
}

@MainActor
final class OverlayWindowController {
    private struct DisplayOverlay {
        let state: OverlayState
        let window: NSWindow
    }

    private let dictionary = DictionaryService()
    private var overlays: [CGDirectDisplayID: DisplayOverlay] = [:]
    private var mouseTimer: Timer?
    private var hoverSpeechTimer: Timer?
    private var currentWord: WordRegion?
    private var autoSpeak = true
    private var hoverDelay = 0.7
    private var translationMode: TranslationMode = .english
    private var explanationMode: ExplanationMode = .english
    private let onSpeakDanish: (String) -> Void

    init(onSpeakDanish: @escaping (String) -> Void) {
        self.onSpeakDanish = onSpeakDanish
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

        let staleDisplayIDs = overlays.keys.filter {
            !activeDisplayIDs.contains($0)
        }
        for displayID in staleDisplayIDs {
            overlays.removeValue(forKey: displayID)?.window.orderOut(nil)
        }

        for (displayID, displayRegions) in grouped {
            guard let screenFrame = displayRegions.first?.screenFrame else {
                continue
            }
            let overlay = overlays[displayID] ?? makeOverlay(frame: screenFrame)
            overlay.state.regions = displayRegions
            overlay.state.screenFrame = screenFrame
            overlay.window.setFrame(screenFrame, display: true)
            overlay.window.orderFrontRegardless()
            overlays[displayID] = overlay
        }

        startMouseTracking()
        updateHover(at: NSEvent.mouseLocation, force: true)
    }

    func hide() {
        for overlay in overlays.values {
            overlay.window.orderOut(nil)
            overlay.state.regions = []
            overlay.state.hoverCard = nil
        }
        currentWord = nil
        mouseTimer?.invalidate()
        mouseTimer = nil
        hoverSpeechTimer?.invalidate()
        hoverSpeechTimer = nil
    }

    private func makeOverlay(frame: CGRect) -> DisplayOverlay {
        let state = OverlayState()
        state.screenFrame = frame
        let rootView = OverlayRootView(state: state)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.contentView = hostingView
        return DisplayOverlay(state: state, window: window)
    }

    private func startMouseTracking() {
        guard mouseTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.updateHover(at: NSEvent.mouseLocation)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func updateHover(
        at point: CGPoint,
        force: Bool = false
    ) {
        var match: (overlay: DisplayOverlay, word: WordRegion)?
        for overlay in overlays.values
        where overlay.state.screenFrame.contains(point) {
            if let word = HoverHitTesting.word(
                at: point,
                in: overlay.state.regions,
                retaining: currentWord
            ) {
                match = (overlay, word)
                break
            }
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
            overlays.values.forEach { $0.state.hoverCard = nil }
            return
        }

        let definition: String
        switch explanationMode {
        case .beginner:
            definition = dictionary.beginnerExplanation(
                for: match.word.translatedText,
                sourceWord: match.word.sourceText
            )
        case .english:
            definition = dictionary.definition(
                for: match.word.translatedText,
                sourceWord: match.word.sourceText
            )
        case .easyDanish:
            definition = match.word.beginnerExplanation.isEmpty
                ? "Ingen kort dansk forklaring fundet."
                : match.word.beginnerExplanation
        case .none:
            definition = ""
        }
        let card = HoverCard(
            word: match.word,
            definition: definition,
            translationMode: translationMode,
            explanationMode: explanationMode
        )
        for overlay in overlays.values
        where overlay.state !== match.overlay.state {
            overlay.state.hoverCard = nil
        }
        if match.overlay.state.hoverCard != card {
            match.overlay.state.hoverCard = card
        }

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
}
