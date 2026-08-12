import Carbon
import Foundation

@main
enum HotKeyConfigurationChecks {
    static func main() {
        var configuration = HotKeyConfiguration.defaults
        precondition(
            configuration.toggleLearning.displayText == "fn Z",
            "Unexpected toggle label: \(configuration.toggleLearning.displayText)"
        )
        precondition(configuration.known.displayText == "1", "Known label")
        precondition(configuration.dontKnow.displayText == "2", "Unknown label")
        precondition(configuration.togglePin.displayText == "3", "Pin label")
        precondition(
            configuration.showAllEnglish.displayText == "4",
            "All-English label"
        )
        precondition(configuration.holdModifier == .option, "Hold modifier")
        precondition(configuration.isValid)

        let replacement = AppShortcut(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: [.command, .shift]
        )
        precondition(
            configuration.conflict(
                for: replacement,
                excluding: .toggleLearning
            ) == nil,
            "Unexpected replacement conflict"
        )
        configuration.set(replacement, for: .toggleLearning)
        precondition(
            configuration.toggleLearning.displayText == "⇧⌘L",
            "Unexpected replacement label: \(configuration.toggleLearning.displayText)"
        )

        let duplicate = configuration.known
        precondition(
            configuration.conflict(
                for: duplicate,
                excluding: .togglePin
            ) == .known,
            "Duplicate shortcut was not detected"
        )

        configuration.holdModifier = .control
        let encoded = try! JSONEncoder().encode(configuration)
        let decoded = try! JSONDecoder().decode(
            HotKeyConfiguration.self,
            from: encoded
        )
        precondition(decoded == configuration, "Shortcut JSON did not round-trip")

        var invalid = configuration
        invalid.togglePin = invalid.known
        precondition(!invalid.isValid)

        // A configuration stored before the all-English shortcut existed must
        // keep every shortcut the learner already chose, not reset the lot.
        // The payload is the real encoding with the newer key removed, so this
        // cannot drift away from what is actually on disk.
        var stored = try! JSONSerialization.jsonObject(
            with: try! JSONEncoder().encode(configuration)
        ) as! [String: Any]
        stored.removeValue(forKey: "showAllEnglish")
        let migrated = try! JSONDecoder().decode(
            HotKeyConfiguration.self,
            from: try! JSONSerialization.data(withJSONObject: stored)
        )
        precondition(
            migrated.toggleLearning == configuration.toggleLearning,
            "Lost the learner's toggle shortcut"
        )
        precondition(
            migrated.holdModifier == configuration.holdModifier,
            "Lost the learner's hold modifier"
        )
        precondition(
            migrated.showAllEnglish == HotKeyConfiguration.defaults.showAllEnglish,
            "Missing shortcut did not fall back to its default"
        )
        precondition(migrated.isValid, "Migrated configuration is unusable")

        print("Editable shortcut configuration checks passed")
    }
}
