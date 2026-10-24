import AppKit
import BabelNews
import SwiftUI

public struct NewsPopupSettingsView: View {
    public static let windowID = "news-card-settings"
    @ObservedObject private var model: AppModel
    public init(model: AppModel) { self.model = model }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("A little Danish, now and then").font(.title2.bold())
                Text("Optional short news cards bring new information to you. Danish stays in front; small hints help with unfamiliar words.").foregroundStyle(.secondary)
                NewsSettings(news: model.news)
            }.padding(24)
        }.frame(minWidth: 460, minHeight: 430)
    }
}

struct NewsPopupView: View {
    @ObservedObject var news: NewsService
    @ObservedObject var translator: NewsTranslationQueue
    @ObservedObject var reader: NewsReadingSupport
    let item: NewsPopupItem
    let close: () -> Void
    let openBook: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("A little Danish").font(.headline)
                Spacer()
                Button("Pause today") { news.pausePopupsForToday(true); close() }.font(.caption)
                Button("Turn off") { news.configurePopups(enabled: false, interval: news.popupPreferences.intervalMinutes); close() }.font(.caption)
                Button(action: close) { Image(systemName: "xmark") }.help("Close this card").accessibilityLabel("Close this card")
            }
            Text("DR news · internet source · adapted locally").font(.caption).foregroundStyle(.secondary).help("Local model: " + item.model)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NewsReadingCardView(news: news, card: NewsCard(article: item.adapted, matches: [], score: 0), compact: true, reader: reader)
                    DisclosureGroup("Original DR headline") { Text(item.original.title).font(.callout).textSelection(.enabled) }
                }
            }
            HStack {
                Button("Listen", systemImage: "speaker.wave.2") { reader.speak?(item.adapted.title) }.disabled(reader.speak == nil)
                Spacer()
                Button("Open Word Book", action: openBook)
            }
        }.padding(16).frame(width: 440, height: 390)
        .background(.background)
        .translationTask(translator.configuration) { await translator.process(using: $0) }
        .onExitCommand(perform: close)
    }
}

/// App-owned utility panel. Creation is separate from presentation for invisible tests.
@MainActor final class NewsPopupController: NSObject, NSWindowDelegate {
    private let news: NewsService
    private let translator: NewsTranslationQueue
    private let openBook: () -> Void
    private var panel: NSPanel?
    private var popupReader: NewsReadingSupport?
    private var timer: Timer?
    private var shownAt = Date()
    private var preview = false
    private var sessionActive = true
    private var observers: [NSObjectProtocol] = []
    var allowed: Bool { sessionActive }
    init(news: NewsService, translator: NewsTranslationQueue, openBook: @escaping () -> Void) {
        self.news = news; self.translator = translator; self.openBook = openBook
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sessionActive = false; self?.dismiss() } })
        }
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sessionActive = true } })
        }
    }
    func makePanel(_ item: NewsPopupItem) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 390), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating; panel.hasShadow = true; panel.collectionBehavior = [.moveToActiveSpace, .transient]
        let reader = news.makePopupReader(); popupReader = reader
        panel.contentView = NSHostingView(rootView: NewsPopupView(news: news, translator: translator, reader: reader, item: item, close: { [weak self] in self?.dismiss() }, openBook: { [weak self] in self?.dismiss(); self?.openBook() }))
        return panel
    }
    func present(_ item: NewsPopupItem) -> Bool {
        guard allowed, panel == nil else { return false }
        let next = makePanel(item); next.delegate = self
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return false }
        next.setFrameOrigin(NSPoint(x: max(area.minX, area.maxX - next.frame.width - 18), y: max(area.minY, area.maxY - next.frame.height - 18)))
        panel = next; preview = item.preview; news.popupVisible = true; shownAt = Date(); next.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkLifetime() } }
        return true
    }
    private func checkLifetime() {
        guard let panel else { return }
        if (!preview && !news.popupPreferences.enabled) || !news.preferences.enabled || (!preview && news.popupsPaused) { dismiss(); return }
        if panel.frame.contains(NSEvent.mouseLocation) || panel.isKeyWindow { shownAt = Date() }
        else if Date().timeIntervalSince(shownAt) >= 45 { dismiss() }
    }
    func dismiss() {
        timer?.invalidate(); timer = nil
        let previous = panel; panel = nil; previous?.close(); news.popupVisible = false
        popupReader?.cancel(); popupReader = nil
    }
    func windowWillClose(_ notification: Notification) { if panel != nil { dismiss() } }
}
