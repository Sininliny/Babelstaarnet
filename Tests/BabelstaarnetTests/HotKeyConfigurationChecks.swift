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
        print("Editable shortcut configuration checks passed")
    }
}
