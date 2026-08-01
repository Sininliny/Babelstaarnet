import Carbon

@main
enum HotKeyRegistrationCheck {
    static func main() {
        checkBubbleNumberHotKeys()

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

    private static func checkBubbleNumberHotKeys() {
        let keys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3]
        var registered: [EventHotKeyRef] = []
        for (index, key) in keys.enumerated() {
            var hotKey: EventHotKeyRef?
            let identifier = EventHotKeyID(
                signature: fourCharacterCode("BCHK"),
                id: UInt32(index + 1)
            )
            let status = RegisterEventHotKey(
                UInt32(key),
                0,
                identifier,
                GetApplicationEventTarget(),
                0,
                &hotKey
            )
            guard status == noErr, let hotKey else {
                registered.forEach { _ = UnregisterEventHotKey($0) }
                print(
                    "Bubble number-key polling fallback check passed "
                        + "(Carbon status \(status))"
                )
                return
            }
            registered.append(hotKey)
        }
        registered.forEach { _ = UnregisterEventHotKey($0) }
        print("Bubble-scoped 1/2/3 Carbon registration check passed")
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
