import AppKit
import BabelNews
import Foundation
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
        news.reader.translate = { $0.map { "English support: " + $0 } }
        var audioCalls = 0
        news.reader.speak = { _ in audioCalls += 1 }; news.reader.saveWord = { _, _, _ in }
        let card = news.cards.first { $0.article.summary.isEmpty }!
        await news.reader.prepare(card.article)
        await news.reader.lookup("får", article: card.article)
        let output = root.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let view = NSHostingView(rootView: NewsReadingCardView(news: news, card: card).padding(16).frame(width: 560))
            view.appearance = NSAppearance(named: appearance)
            let size = view.fittingSize
            precondition(size.width >= 500 && size.height > 200 && size.height < 1100, "News reading controls must fit a normal Word Book window")
            view.setFrameSize(size); view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { preconditionFailure("News card could not render") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("mac-news-" + name + ".png"))
        }
        precondition(audioCalls == 0, "Opening a news card must never autoplay speech")
        print("Native news cards rendered light/dark without windows, desktop capture or audio.")
    }
}
