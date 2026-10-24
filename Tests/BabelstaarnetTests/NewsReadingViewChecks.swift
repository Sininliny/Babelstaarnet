import AppKit
import BabelNews
import Foundation
import LanguageDanish
import SwiftUI
@testable import BabelstaarnetKit

@main @MainActor enum NewsReadingViewChecks {
    static func main() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("news-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let xml = try String(contentsOf: root.appendingPathComponent("Tests/Shared/news-feed.xml"), encoding: .utf8)
        let date = ISO8601DateFormatter().date(from: "2026-10-22T12:00:00Z")!
        let news = NewsService(directory: directory, clock: { date }, download: { _ in xml })
        news.configure(enabled: true, background: false, notify: false, topic: 0, hour: 18); await news.refresh()
        news.reader.translate = { texts in texts.map { text in
            if text.hasPrefix("Regeringen") { return "The government presents a new plan for green energy." }
            if text.hasPrefix("Æbler") { return "Apples and sheep in the countryside." }
            if text == "får" { return "sheep" }
            return "A short and clear message."
        } }
        let glosses = ["æbler": "apples", "og": "and", "får": "sheep", "på": "in", "landet": "the countryside"]
        news.reader.cachedWordMeaning = { glosses[$0.lowercased()] }
        news.reader.knowledgeLevel = { ["æbler", "og"].contains($0.lowercased()) ? 4 : 0 }
        var audioCalls = 0
        news.reader.speak = { _ in audioCalls += 1 }; news.reader.saveWord = { _, _, _ in }
        let card = news.cards.first { $0.article.summary.isEmpty }!
        await news.reader.prepare(card.article)
        precondition(!news.reader.isVisible(card.article) && news.reader.meaning(card.article) == nil)
        let output = root.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for help in [false, true] {
            if help { await news.reader.prepare(card.article, requested: true) }
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                let view = NSHostingView(rootView: NewsReadingCardView(news: news, card: card).padding(16).frame(width: 560))
                view.appearance = NSAppearance(named: appearance)
                let size = view.fittingSize
                precondition(size.width >= 500 && size.height > 200 && size.height < 1100, "News reading controls must fit a normal Word Book window")
                view.setFrameSize(size); view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { preconditionFailure("News card could not render") }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("mac-news-" + name + (help ? "-sentence-help" : "") + ".png"))
            }
        }
        let translator = NewsTranslationQueue(languages: .danishToEnglish)
        let item = NewsPopupItem(original: card.article, text: "Æbler og får på landet", model: "fixture local AI")
        let popupReader = news.makePopupReader()
        precondition(news.reader.isVisible(card.article) && !popupReader.isVisible(item.adapted), "Popup and Word Book reading states must be independent")
        let controller = NewsPopupController(news: news, translator: translator, openBook: {})
        let panel = controller.makePanel(item)
        precondition(!panel.isVisible && panel.styleMask.contains(.nonactivatingPanel), "Creating a popup must not activate a test window")
        panel.close()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let host = NSHostingView(rootView: NewsPopupView(news: news, translator: translator, reader: news.makePopupReader(), item: item, close: {}, openBook: {}))
            host.appearance = NSAppearance(named: appearance); host.setFrameSize(NSSize(width: 440, height: 390)); host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { preconditionFailure("News popup could not render") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("mac-news-popup-" + name + ".png"))
        }
        precondition(audioCalls == 0, "Opening a news card must never autoplay speech")
        print("Native news cards rendered light/dark without windows, desktop capture or audio.")
    }
}
