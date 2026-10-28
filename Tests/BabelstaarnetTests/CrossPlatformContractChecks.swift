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
        struct Scaffold: Decodable { let title: String; let levels: [String: Int]; let meanings: [String: String]; let hints: [String: String] }
        struct Popup: Decodable { let id: String; let enabled, background, optedIn, blocked: Bool; let hour: Int; let elapsed: Double; let interval, shown, fresh: Int; let due: Bool }
        struct Units: Decodable { let text: String; let words: [String] }
        let readingUnits: [Units]
        let newsPopupSchedule: [Popup]
        let newsScaffolding: [Scaffold]
        let newsReading: [News]
        let learningPresentation: [Presentation]
        let schemaVersion: Int
        let identities: [Identity]
        let sentences: [Sentence]
    }
    @MainActor static func main() async throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Shared/reading-contract.json")
        let contract = try JSONDecoder().decode(Contract.self, from: Data(contentsOf: path))
        precondition(contract.schemaVersion == 1)
        let language = SourceLanguage.danish
        let boundary = SentenceBoundary(rules: language.sentenceRules, locale: language.locale)
        for item in contract.readingUnits { precondition(ReadingText.words(in: item.text) == item.words) }
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
        for item in contract.newsScaffolding {
            let xml = "<rss><channel><item><title>Fixture</title><link>https://www.dr.dk/nyheder/fixture</link><pubDate>Thu, 22 Oct 2026 10:00:00 GMT</pubDate></item></channel></rss>"
            var article = try NewsService.parseFeed(xml, topic: 0)[0]; article.title = item.title
            let reader = NewsReadingSupport(directory: FileManager.default.temporaryDirectory.appendingPathComponent("scaffold-\(UUID())"))
            reader.cachedWordMeaning = { item.meanings[$0.lowercased()] }
            reader.knowledgeLevel = { item.levels[$0.lowercased()] ?? 0 }
            reader.translate = { _ in preconditionFailure("Available dictionary hints need no translation work") }
            await reader.prepare(article)
            for word in NewsReadingSupport.pieces(item.title).compactMap(NewsReadingSupport.word) {
                precondition(reader.gloss(word, article: article) == item.hints[word.lowercased()], "Unfamiliar words get hints; known words and names remain Danish")
            }
            precondition(!reader.isVisible(article) && reader.meaning(article) == nil)
        }
        for item in contract.newsPopupSchedule {
            precondition(SharedPolicy.newsPopupDue(enabled: item.enabled, background: item.background, optedIn: item.optedIn, blocked: item.blocked, hour: item.hour, elapsed: item.elapsed, interval: item.interval, shown: item.shown, fresh: item.fresh) == item.due, "Shared news popup: " + item.id)
        }
        print("Cross-platform Danish contract passed")
    }
}
