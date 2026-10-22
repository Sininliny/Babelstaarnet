import BabelCore
import Foundation
import LanguageDanish

@main
enum CrossPlatformContractChecks {
    struct Contract: Decodable {
        struct Identity: Decodable { let text: String; let key: String }
        struct Sentence: Decodable { let text: String; let stops: Int; let ends: Bool }
        struct Presentation: Decodable { let level: Int; let supported: Bool; let focus: Bool; let newSense: Bool; let cooldown: Bool; let selected: Bool; let anchor: Bool }
        let learningPresentation: [Presentation]
        let schemaVersion: Int
        let identities: [Identity]
        let sentences: [Sentence]
    }
    static func main() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Shared/reading-contract.json")
        let contract = try JSONDecoder().decode(Contract.self, from: Data(contentsOf: path))
        precondition(contract.schemaVersion == 1)
        let language = SourceLanguage.danish
        let boundary = SentenceBoundary(rules: language.sentenceRules, locale: language.locale)
        for item in contract.identities {
            precondition(language.normalized(item.text) == item.key, "Shared word identity: \(item.text)")
        }
        for item in contract.sentences {
            precondition(boundary.stopLocations(in: item.text).count == item.stops, "Shared sentence stops: \(item.text)")
            precondition(boundary.endsSentence(item.text) == item.ends, "Shared sentence ending: \(item.text)")
        }
        for item in contract.learningPresentation {
            precondition(SharedPolicy.anchor(level: item.level, supported: item.supported, focus: item.focus, newSense: item.newSense, cooldown: item.cooldown, selected: item.selected) == item.anchor)
        }
        print("Cross-platform Danish contract passed")
    }
}
