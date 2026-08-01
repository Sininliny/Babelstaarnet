import AppKit
import Carbon
import Foundation

@MainActor
final class HotKeyService {
    private static let signature = fourCharacterCode("BSTR")
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var keyStateTimer: Timer?
    private var chordWasDown = false
    private var shortcut = HotKeyConfiguration.defaults.toggleLearning
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register(shortcut: AppShortcut) {
        unregister()
        self.shortcut = shortcut

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(self).toOpaque()
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == HotKeyService.signature,
                      hotKeyID.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }

                let service = Unmanaged<HotKeyService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    service.action()
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )

        let identifier = EventHotKeyID(
            signature: Self.signature,
            id: 1
        )
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers.carbonFlags,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if status != noErr {
            startPollingFallback()
        }
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        keyStateTimer?.invalidate()
        keyStateTimer = nil
        chordWasDown = false
    }

    deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        keyStateTimer?.invalidate()
    }

    private func startPollingFallback() {
        let timer = Timer(timeInterval: 0.04, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.pollShortcut()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        keyStateTimer = timer
    }

    private func pollShortcut() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let chordDown = shortcut.isPressed(using: flags)

        if chordDown, !chordWasDown {
            action()
        }
        chordWasDown = chordDown
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
