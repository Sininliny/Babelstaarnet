import BabelCore
import BabelNews
import BabelPolicy
import Foundation
import LanguageDanish

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
            case "news-gloss": result = Double(bp_news_gloss(i(0),i(1),i(2)))
            case "reading-help": result = Double(bp_reading_help(i(0),i(1),i(2),i(3)))
            case "retry": result = Double(bp_retry_delay(i(0)))
            case "source": result = Double(bp_source_capability(i(0)))
            case "summary": result = SharedPolicy.summaryValid(source: s(0), summary: s(1), preservationWords: SourceLanguage.danish.meaningPreservationWords) ? 1 : 0
            case "target": result = Double(bp_target_allowed(i(0),i(1)))
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
        news.meaningPreservationWords = SourceLanguage.danish.meaningPreservationWords
        var reading = true, generations = 0
        news.readingActive = { reading }; news.modelAvailable = { true }; news.modelIdentity = { "fixture-v1" }
        news.simplifyExcerpt = { _ in generations += 1; return "En tydelig besked." }
        await news.simplify(parsed[0]); precondition(generations == 0)
        reading = false; await news.simplify(parsed[0]); await news.simplify(parsed[0])
        precondition(generations == 1 && news.simplifiedText(for: parsed[0]) == "En tydelig besked." && news.simplifiedModel(for: parsed[0]) == "fixture-v1")
        let restored = NewsService(directory: directory, clock: { now }, download: { _ in preconditionFailure("Cache accessed HTTP") })
        restored.meaningPreservationWords = news.meaningPreservationWords
        precondition(restored.simplifiedText(for: parsed[0]) == "En tydelig besked.")
        news.configure(enabled: true, background: true, notify: true, topic: 0, hour: 18)
        news.pageVisible = true; await news.refresh(manual: true, background: true); precondition(downloads == 1)
        news.pageVisible = false
        news.configure(enabled: false, background: true, notify: true, topic: 0, hour: 18)
        await news.refresh(manual: true, background: true)
        precondition(downloads == 1 && !news.preferences.background && !news.preferences.notify)
        let reader = news.reader
        var translations = 0, spoken = 0, savedContext = ""
        reader.translate = { texts in translations += 1; return texts.map { "English: " + $0 } }
        reader.speak = { _ in spoken += 1 }; reader.saveWord = { _, _, context in savedContext = context }
        let headlineOnly = parsed.first { $0.summary.isEmpty }!
        precondition(!reader.isVisible(headlineOnly))
        await reader.prepare(headlineOnly); await reader.prepare(headlineOnly)
        precondition(translations == 1 && reader.meaning(headlineOnly) == nil && !reader.isVisible(headlineOnly), "Default support must translate words, never a full English alternative")
        await reader.prepare(headlineOnly, requested: true)
        precondition(reader.isVisible(headlineOnly) && translations == 2 && reader.meaning(headlineOnly)?.parts.count == 1)
        reader.hideTranslation(headlineOnly); await reader.prepare(headlineOnly)
        precondition(!reader.isVisible(headlineOnly) && translations == 2)
        await reader.prepare(headlineOnly, requested: true); precondition(translations == 2)
        await reader.lookup("får", article: headlineOnly); reader.saveSelection(article: headlineOnly)
        precondition(reader.selected?.meaning == "English: får" && savedContext.contains(headlineOnly.title) && spoken == 0)
        // Legacy English-on files retain their useful cache, never their automatic reveal.
        let file = directory.appendingPathComponent("news-reading.json")
        var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        legacy["showEnglish"] = true; try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        let restoredReading = NewsReadingSupport(directory: directory)
        precondition(!restoredReading.isVisible(headlineOnly) && restoredReading.meaning(headlineOnly) != nil)
        restoredReading.translate = { _ in preconditionFailure("Cached help must not rerun an engine") }
        await restoredReading.prepare(headlineOnly); await restoredReading.prepare(headlineOnly, requested: true)
        precondition(restoredReading.isVisible(headlineOnly))
        reader.cancel(); precondition(!reader.isVisible(headlineOnly))
        var changed = headlineOnly; changed.title += " - updated"
        precondition(restoredReading.meaning(changed) == nil)
        var started = false
        reader.translate = { texts in started = true; try await Task.sleep(for: .seconds(10)); return texts }
        let pending = Task { await reader.prepare(changed, requested: true) }
        while !started { await Task.yield() }
        reader.cancel()
        reader.translate = { $0.map { "Fresh: " + $0 } }; await reader.prepare(changed, requested: true); await pending.value
        precondition(reader.meaning(changed)?.parts.first?.hasPrefix("Fresh:") == true)
        changed.title = "Incomplete fixture"; reader.translate = { _ in [] }; await reader.prepare(changed, requested: true)
        precondition(reader.meaning(changed) == nil && reader.state(changed)?.contains("unavailable") == true)
        var level = 0
        reader.knowledgeLevel = { _ in level }; reader.cachedWordMeaning = { _ in "hint" }
        await reader.prepare(changed); level = 5
        precondition(reader.gloss("Incomplete", article: changed) == "hint", "Learning elsewhere must not withdraw already displayed help")
        reader.cancel(); await reader.prepare(changed)
        precondition(reader.gloss("Incomplete", article: changed) == nil, "A new visit uses the updated knowledge level")
        news.simplifyExcerpt = { $0 }; await news.simplify(headlineOnly)
        precondition(news.simplifiedText(for: headlineOnly) == headlineOnly.title)
        await reader.lookup("ny", article: headlineOnly, context: "En ny park.")
        precondition(reader.selected?.context == "En ny park.")
        print("Passed \(count) shared native policy vectors and offline news adapter checks.")
    }
}
