import AppKit
import Carbon

enum BubbleHotKeyAction: UInt32, CaseIterable {
    case known = 1
    case dontKnow = 2
    case togglePin = 3

    var keyCode: UInt32 {
        switch self {
        case .known:
            UInt32(kVK_ANSI_1)
        case .dontKnow:
            UInt32(kVK_ANSI_2)
        case .togglePin:
            UInt32(kVK_ANSI_3)
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
    private let action: (BubbleHotKeyAction) -> Void

    init(action: @escaping (BubbleHotKeyAction) -> Void) {
        self.action = action
    }

    func register() {
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
                Task { @MainActor in
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
                action.keyCode,
                0,
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
            Task { @MainActor in
                self?.pollNumberKeys()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        keyStateTimer = timer
    }

    private func pollNumberKeys() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let hasDisallowedModifier = flags.contains(.maskCommand)
            || flags.contains(.maskControl)
            || flags.contains(.maskAlternate)
            || flags.contains(.maskShift)
        var keysDown = Set<BubbleHotKeyAction>()
        for candidate in BubbleHotKeyAction.allCases {
            let isDown = CGEventSource.keyState(
                .combinedSessionState,
                key: CGKeyCode(candidate.keyCode)
            )
            if isDown {
                keysDown.insert(candidate)
                if !hasDisallowedModifier,
                   !keysPreviouslyDown.contains(candidate) {
                    action(candidate)
                }
            }
        }
        keysPreviouslyDown = keysDown
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
