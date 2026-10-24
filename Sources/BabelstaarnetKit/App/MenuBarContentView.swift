import AppKit
import BabelNews
import SwiftUI

/// A native first-level status menu: daily actions remain outside Settings.
public struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var news: NewsService
    @Environment(\.openWindow) private var openWindow
    public init(model: AppModel) { self.model = model; news = model.news }
    public var body: some View {
        Button("Word Book") { model.openWordBook() }.keyboardShortcut("b", modifiers: [.command, .shift])
        Button("Read something new") { model.openNewsBook() }
        Button(news.popupsPaused ? "News cards · paused today…" : "Scheduled news cards…") {
            openWindow(id: NewsPopupSettingsView.windowID); NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        if model.screenPermissionGranted {
            Button(model.learningModeActive ? "Stop translating" : "Start translating") { Task { await model.toggleLearningMode() } }
            Menu("Reading options") {
                Toggle("Word meaning", isOn: Binding(get: { model.bridgeConfiguration.showsWordBridge }, set: model.setWordBridgeEnabled))
                Toggle("Whole sentence", isOn: Binding(get: { model.bridgeConfiguration.showsSentenceBridge }, set: model.setSentenceBridgeEnabled))
                Text("Start / stop: " + model.toggleLearningShortcutLabel)
                ForEach(model.bubbleShortcutHints, id: \.label) { Text($0.key + " · " + $0.label) }
            }
            if let message = model.failureMessage { Text(message) }
        } else {
            Button(model.screenPermissionWasRequested ? "Open screen access settings" : "Set up screen reading") {
                if model.screenPermissionWasRequested { model.openScreenRecordingSettings() } else { model.beginGuidedSetup() }
            }
            if model.screenPermissionWasRequested { Button("Enabled it? Relaunch") { model.relaunch() } }
        }
        Divider()
        SettingsLink { Text("Settings…") }
        Button("Quit Babelstårnet") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}

public struct WordBookCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    public init() {}
    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Word Book") { openWindow(id: WordBookView.windowID); NSApp.activate(ignoringOtherApps: true) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
        }
    }
}
