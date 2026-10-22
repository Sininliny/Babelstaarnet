import BabelCore
import BabelNews
import BabelPolicy
import Foundation

@main enum SharedPolicyChecks {
    @MainActor static func main() async throws {
        let shared = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Shared")
        let data = try Data(contentsOf: shared.appendingPathComponent("policy-runtime.json"))
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var count = 0
        for item in root["cases"] as! [[String: Any]] {
            let args = item["args"] as! [Any]
            func i(_ n: Int) -> Int32 { (args[n] as! NSNumber).int32Value }
            func d(_ n: Int) -> Double { (args[n] as! NSNumber).doubleValue }
            func s(_ n: Int) -> String { args[n] as! String }
            let result: Double
            switch item["operation"] as! String {
            case "anchor": result = Double(bp_anchor(i(0),i(1),i(2),i(3),i(4),i(5)))
            case "challenge": result = Double(bp_challenge(i(0),i(1),i(2),i(3),i(4),i(5)))
            case "fetch": result = Double(bp_fetch(i(0),i(1),i(2),i(3),d(4),d(5)))
            case "digest": result = Double(bp_digest(i(0),i(1),i(2),i(3),i(4),i(5),i(6),i(7)))
            case "evidence": result = Double(bp_evidence(i(0),i(1),i(2)))
            case "rewrite": result = Double(bp_rewrite(i(0),i(1),i(2),i(3),i(4)))
            case "score": result = bp_news_score(d(0),d(1),d(2),d(3),i(4))
            case "contains": result = SharedPolicy.contains(s(0), unit: s(1)) ? 1 : 0
            case "story": result = SharedPolicy.sameStory(s(0),s(1)) ? 1 : 0
            default: fatalError("Unknown shared policy operation")
            }
            precondition(abs(result - (item["expected"] as! NSNumber).doubleValue) < 0.000001, "Shared vector \(item["id"]!)")
            count += 1
        }
        let xml = try String(contentsOf: shared.appendingPathComponent("news-feed.xml"), encoding: .utf8)
        let parsed = try NewsService.parseFeed(xml, topic: 0)
        precondition(parsed.count == 3 && parsed[0].summary == "En kort & tydelig besked.")
        do { _ = try NewsService.parseFeed("<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///private'>]><rss/>", topic: 0); preconditionFailure("DTD accepted") } catch { }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("babel-news-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        var downloads = 0
        let now = ISO8601DateFormatter().date(from: "2026-10-22T12:00:00Z")!
        let news = NewsService(directory: directory, clock: { now }, download: { _ in downloads += 1; return xml })
        news.learningUnits = { ["æbler", "energi"] }
        await news.refresh(manual: true); precondition(downloads == 0)
        news.configure(enabled: true, background: false, notify: false, topic: 0, hour: 18)
        await news.refresh(); precondition(downloads == 1 && news.cards.count == 2)
        await news.refresh(); precondition(downloads == 1)
        news.configure(enabled: false, background: true, notify: true, topic: 0, hour: 18)
        await news.refresh(manual: true, background: true)
        precondition(downloads == 1 && !news.preferences.background && !news.preferences.notify)
        print("Passed \(count) shared native policy vectors and offline news adapter checks.")
    }
}
