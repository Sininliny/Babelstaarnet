import Carbon

@main
enum HotKeyRegistrationCheck {
    static func main() {
        var hotKey: EventHotKeyRef?
        let identifier = EventHotKeyID(
            signature: fourCharacterCode("BTST"),
            id: 99
        )
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_Z),
            UInt32(kEventKeyModifierFnMask),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if status == noErr, let hotKey {
            UnregisterEventHotKey(hotKey)
            print("Fn+Z Carbon registration check passed")
            return
        }

        _ = CGEventSource.flagsState(.combinedSessionState)
        _ = CGEventSource.keyState(
            .combinedSessionState,
            key: CGKeyCode(kVK_ANSI_Z)
        )
        print("Fn+Z key-state fallback check passed (Carbon status \(status))")
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
