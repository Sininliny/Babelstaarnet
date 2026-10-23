import BabelCore
import BabelNews
import Foundation
import LanguageDanish

@main
enum CrossPlatformContractChecks {
    struct Contract: Decodable {
        struct Identity: Decodable { let text: String; let key: String }
        struct Sentence: Decodable { let text: String; let stops: Int; let ends: Bool }
        struct Presentation: Decodable { let level: Int; let supported: Bool; let focus: Bool; let newSense: Bool; let cooldown: Bool; let selected: Bool; let anchor: Bool }
        struct News: Decodable { let title: String; let summary: String; let parts: [String]; let pieces: [String]; let words: [String?] }
        let newsReading: [News]
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
        for item in contract.newsReading {
            let xml = "<rss><channel><item><title>Fixture</title><link>https://www.dr.dk/nyheder/fixture</link><pubDate>Thu, 22 Oct 2026 10:00:00 GMT</pubDate></item></channel></rss>"
            var article = try NewsService.parseFeed(xml, topic: 0)[0]; article.title = item.title; article.summary = item.summary
            precondition(NewsReadingSupport.sourceParts(article) == item.parts)
            let pieces = NewsReadingSupport.pieces(item.title)
            precondition(pieces == item.pieces && pieces.map { NewsReadingSupport.word($0) } == item.words)
        }
        print("Cross-platform Danish contract passed")
    }
}
