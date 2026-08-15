import AppKit
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: AppShortcut
    let onChange: (AppShortcut) -> Bool

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onChange = onChange
        button.setShortcut(shortcut)
        return button
    }

    func updateNSView(
        _ nsView: ShortcutRecorderButton,
        context: Context
    ) {
        nsView.onChange = onChange
        if !nsView.isRecording {
            nsView.setShortcut(shortcut)
        }
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    var onChange: (AppShortcut) -> Bool = { _ in false }
    private(set) var isRecording = false
    private var shortcut = HotKeyConfiguration.defaults.toggleLearning

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        controlSize = .small
        font = .systemFont(ofSize: 11, weight: .medium)
        target = self
        action = #selector(beginRecording)
        setAccessibilityLabel("Record keyboard shortcut")
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    func setShortcut(_ shortcut: AppShortcut) {
        self.shortcut = shortcut
        title = shortcut.displayText
        toolTip = "Click, then press the new shortcut"
    }

    @objc private func beginRecording() {
        isRecording = true
        title = "Press shortcut"
        toolTip = "Press Escape to cancel"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        guard !event.isARepeat else {
            return
        }
        if event.keyCode == 53 {
            finishRecording()
            return
        }
        let recorded = AppShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: HotKeyModifiers(eventFlags: event.modifierFlags)
        )
        if onChange(recorded) {
            shortcut = recorded
        }
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    private func finishRecording() {
        isRecording = false
        setShortcut(shortcut)
    }
}
