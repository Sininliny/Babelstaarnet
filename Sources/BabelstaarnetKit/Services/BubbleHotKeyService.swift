import AppKit
import Carbon
import BabelCore
import BabelLexicon
import BabelOCR
import BabelSpeech
import BabelTranslate
import LanguageDanish

enum BubbleHotKeyAction: UInt32, CaseIterable {
    case known = 1
    case dontKnow = 2
    case togglePin = 3

    var configurableAction: ConfigurableHotKeyAction {
        switch self {
        case .known:
            .known
        case .dontKnow:
            .dontKnow
        case .togglePin:
            .togglePin
        }
    }
}

@MainActor
final class BubbleHotKeyService {
    private static let signature = fourCharacterCode("BBLE")

    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var keyStateTimer: Timer?
    private var keysPreviouslyDown = Set<BubbleHotKeyAction>()
    private var configuration = HotKeyConfiguration.defaults
    private let action: (BubbleHotKeyAction) -> Void

    init(action: @escaping (BubbleHotKeyAction) -> Void) {
        self.action = action
    }

    func register(configuration: HotKeyConfiguration) {
        if self.configuration != configuration {
            unregister()
            self.configuration = configuration
        }
        guard hotKeys.isEmpty,
              eventHandler == nil,
              keyStateTimer == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(self).toOpaque()
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr,
                      identifier.signature == BubbleHotKeyService.signature,
                      let action = BubbleHotKeyAction(
                        rawValue: identifier.id
                      ) else {
                    return OSStatus(eventNotHandledErr)
                }
                let service = Unmanaged<BubbleHotKeyService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    service.action(action)
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )

        guard handlerStatus == noErr else {
            eventHandler = nil
            installPollingFallback()
            return
        }

        for action in BubbleHotKeyAction.allCases {
            var hotKey: EventHotKeyRef?
            let identifier = EventHotKeyID(
                signature: Self.signature,
                id: action.rawValue
            )
            let status = RegisterEventHotKey(
                shortcut(for: action).keyCode,
                shortcut(for: action).modifiers.carbonFlags,
                identifier,
                GetApplicationEventTarget(),
                0,
                &hotKey
            )
            guard status == noErr, let hotKey else {
                unregisterCarbonHotKeys()
                installPollingFallback()
                return
            }
            hotKeys.append(hotKey)
        }
    }

    func unregister() {
        unregisterCarbonHotKeys()
        keyStateTimer?.invalidate()
        keyStateTimer = nil
        keysPreviouslyDown.removeAll()
    }

    deinit {
        hotKeys.forEach { _ = UnregisterEventHotKey($0) }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        keyStateTimer?.invalidate()
    }

    private func unregisterCarbonHotKeys() {
        hotKeys.forEach { _ = UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func installPollingFallback() {
        let timer = Timer(timeInterval: 0.04, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollNumberKeys()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        keyStateTimer = timer
    }

    private func pollNumberKeys() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        var keysDown = Set<BubbleHotKeyAction>()
        for candidate in BubbleHotKeyAction.allCases {
            let isDown = shortcut(for: candidate).isPressed(using: flags)
            if isDown {
                keysDown.insert(candidate)
                if !keysPreviouslyDown.contains(candidate) {
                    action(candidate)
                }
            }
        }
        keysPreviouslyDown = keysDown
    }

    private func shortcut(for action: BubbleHotKeyAction) -> AppShortcut {
        configuration.shortcut(for: action.configurableAction)
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
