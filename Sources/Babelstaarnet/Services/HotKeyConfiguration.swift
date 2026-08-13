import AppKit
import Carbon
import Foundation

struct HotKeyModifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
    let rawValue: UInt32

    static let command = Self(rawValue: 1 << 0)
    static let control = Self(rawValue: 1 << 1)
    static let option = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
    static let function = Self(rawValue: 1 << 4)
    private static let supportedMask = command.rawValue
        | control.rawValue
        | option.rawValue
        | shift.rawValue
        | function.rawValue

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var value: Self = []
        if eventFlags.contains(.command) { value.insert(.command) }
        if eventFlags.contains(.control) { value.insert(.control) }
        if eventFlags.contains(.option) { value.insert(.option) }
        if eventFlags.contains(.shift) { value.insert(.shift) }
        if eventFlags.contains(.function) { value.insert(.function) }
        self = value
    }

    var carbonFlags: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        if contains(.function) {
            result |= UInt32(kEventKeyModifierFnMask)
        }
        return result
    }

    var containsOnlySupportedFlags: Bool {
        rawValue & ~Self.supportedMask == 0
    }

    var displayPrefix: String {
        var result = ""
        if contains(.function) { result += "fn " }
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    func matches(_ flags: CGEventFlags) -> Bool {
        let actual = HotKeyModifiers(cgEventFlags: flags)
        return actual == self
    }

    private init(cgEventFlags: CGEventFlags) {
        var value: Self = []
        if cgEventFlags.contains(.maskCommand) { value.insert(.command) }
        if cgEventFlags.contains(.maskControl) { value.insert(.control) }
        if cgEventFlags.contains(.maskAlternate) { value.insert(.option) }
        if cgEventFlags.contains(.maskShift) { value.insert(.shift) }
        if cgEventFlags.contains(.maskSecondaryFn) {
            value.insert(.function)
        }
        self = value
    }
}

struct AppShortcut: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: HotKeyModifiers

    var displayText: String {
        modifiers.displayPrefix + Self.keyName(for: keyCode)
    }

    var isValid: Bool {
        keyCode <= 127 && modifiers.containsOnlySupportedFlags
    }

    func isPressed(using flags: CGEventFlags) -> Bool {
        modifiers.matches(flags)
            && CGEventSource.keyState(
                .combinedSessionState,
                key: CGKeyCode(keyCode)
            )
    }

    static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space", UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Return): "Return", UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "Forward Delete",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "Home", UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "Page Up", UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`"
    ]
}

/// Declared in the order the default shortcuts run, 1 through 4, because that
/// order is what Settings lists and what the menu-bar popover prints. Showing
/// all English came first and carried `4`, so every surface read 4, 1, 2, 3.
/// The raw values are the case names, so persisted shortcuts are unaffected.
enum ConfigurableHotKeyAction: String, CaseIterable, Identifiable, Sendable {
    case toggleLearning
    case known
    case dontKnow
    case togglePin
    case showAllEnglish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleLearning: "Toggle hover translation"
        case .showAllEnglish: "Show all English"
        case .known: "Knew"
        case .dontKnow: "Don’t know"
        case .togglePin: "Pin or unpin"
        }
    }

    var requiresModifier: Bool {
        self == .toggleLearning
    }
}

enum BubbleHoldModifier: String, CaseIterable, Codable, Identifiable, Sendable {
    case option
    case command
    case control
    case shift
    case function

    var id: String { rawValue }

    var title: String {
        switch self {
        case .option: "Option"
        case .command: "Command"
        case .control: "Control"
        case .shift: "Shift"
        case .function: "Fn"
        }
    }

    func isPressed(in flags: CGEventFlags) -> Bool {
        switch self {
        case .option: flags.contains(.maskAlternate)
        case .command: flags.contains(.maskCommand)
        case .control: flags.contains(.maskControl)
        case .shift: flags.contains(.maskShift)
        case .function: flags.contains(.maskSecondaryFn)
        }
    }
}

struct HotKeyConfiguration: Codable, Equatable, Sendable {
    var toggleLearning: AppShortcut
    var showAllEnglish: AppShortcut
    var known: AppShortcut
    var dontKnow: AppShortcut
    var togglePin: AppShortcut
    var holdModifier: BubbleHoldModifier

    static let defaults = Self(
        toggleLearning: AppShortcut(
            keyCode: UInt32(kVK_ANSI_Z),
            modifiers: [.function]
        ),
        showAllEnglish: AppShortcut(
            keyCode: UInt32(kVK_ANSI_4),
            modifiers: []
        ),
        known: AppShortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: []),
        dontKnow: AppShortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: []),
        togglePin: AppShortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: []),
        holdModifier: .option
    )

    var isValid: Bool {
        guard !toggleLearning.modifiers.isEmpty else {
            return false
        }
        let shortcuts = ConfigurableHotKeyAction.allCases.map {
            shortcut(for: $0)
        }
        return shortcuts.allSatisfy(\.isValid)
            && Set(shortcuts).count == shortcuts.count
    }

    func shortcut(for action: ConfigurableHotKeyAction) -> AppShortcut {
        switch action {
        case .toggleLearning: toggleLearning
        case .showAllEnglish: showAllEnglish
        case .known: known
        case .dontKnow: dontKnow
        case .togglePin: togglePin
        }
    }

    mutating func set(
        _ shortcut: AppShortcut,
        for action: ConfigurableHotKeyAction
    ) {
        switch action {
        case .toggleLearning: toggleLearning = shortcut
        case .showAllEnglish: showAllEnglish = shortcut
        case .known: known = shortcut
        case .dontKnow: dontKnow = shortcut
        case .togglePin: togglePin = shortcut
        }
    }

    func conflict(
        for shortcut: AppShortcut,
        excluding action: ConfigurableHotKeyAction
    ) -> ConfigurableHotKeyAction? {
        ConfigurableHotKeyAction.allCases.first {
            $0 != action && self.shortcut(for: $0) == shortcut
        }
    }
}

// Declared in an extension so the memberwise initializer above survives.
extension HotKeyConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toggleLearning = try container.decode(
            AppShortcut.self,
            forKey: .toggleLearning
        )
        // Added after the first release. A stored configuration written before
        // it existed is still valid; dropping the whole thing would silently
        // reset every shortcut the learner had already chosen.
        showAllEnglish = try container.decodeIfPresent(
            AppShortcut.self,
            forKey: .showAllEnglish
        ) ?? Self.defaults.showAllEnglish
        known = try container.decode(AppShortcut.self, forKey: .known)
        dontKnow = try container.decode(AppShortcut.self, forKey: .dontKnow)
        togglePin = try container.decode(AppShortcut.self, forKey: .togglePin)
        holdModifier = try container.decode(
            BubbleHoldModifier.self,
            forKey: .holdModifier
        )
    }
}
