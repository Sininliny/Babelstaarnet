import BabelCore
import Combine
import Foundation
import CryptoKit
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct NewsArticle: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var url: String
    public var published: Double
    public var topic: Int
    public var publishedDate: Date { Date(timeIntervalSince1970: published) }
    public var valid: Bool {
        guard let link = URL(string: url) else { return false }
        return !title.isEmpty && title.count <= 350 && summary.count <= 3000 && id.count < 512 && published.isFinite &&
            link.scheme == "https" && link.host == "www.dr.dk" && link.user == nil && link.password == nil &&
            (link.port == nil || link.port == 443) && link.path.hasPrefix("/nyheder/") && (0..<8).contains(topic)
    }
}
public struct NewsCard: Identifiable {
    public var article: NewsArticle
    public var matches: [String]
    public var score: Double
    public var id: String { article.id }
}
public struct NewsPopupPreferences: Codable {
    public var enabled = false
    public var intervalMinutes = 120
    public var lastShown: Double?
    public var day: String?
    public var shown = 0
    public var ids: [String] = []
    public var pausedUntil: Double?
}
public struct NewsPopupItem {
    public let original: NewsArticle
    public let adapted: NewsArticle
    public let model: String
    public let preview: Bool
    public init(original: NewsArticle, text: String, model: String, preview: Bool = false) {
        self.original = original; self.model = model; self.preview = preview
        var adapted = original; adapted.title = text; adapted.summary = ""; self.adapted = adapted
    }
}
public struct NewsPreferences: Codable {
    public var popup: NewsPopupPreferences?
    public var enabled = false
    public var background = false
    public var notify = false
    public var topic = 0
    public var digestHour = 18
    public var lastDigestDay: String?
    public var lastDigestIds: [String]?
    public var lastBookPage: Int?
}
private struct NewsShortVersion: Codable {
    var text: String
    var model: String
    var created: Double
}
private struct NewsCache: Codable {
    var fetched: Double = 0
    var topic = 0
    var articles: [NewsArticle] = []
    var seen: [String: Double] = [:]
    var seenTitles: [String: Double] = [:]
    var shortVersions: [String: NewsShortVersion]?
}
private final class NewsRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Native network/storage adapter. Decisions come from the same C component as Windows.
@MainActor public final class NewsService: ObservableObject {
    public let reader: NewsReadingSupport
    public static let topics = ["Latest", "Denmark", "World", "Money", "Politics", "Science", "Culture", "Sport"]
    public static let disclosure = "Connects to DR to fetch public news. Matching stays on this Mac. No word list, screenshots or learning records are uploaded. DR receives ordinary requests, including your IP address and requested URLs. Opening an original uses your browser."
    @Published public private(set) var preferences: NewsPreferences
    @Published public private(set) var cards: [NewsCard] = []
    @Published public private(set) var busy = false
    @Published public private(set) var status = "News is optional. Enable it to connect to DR."
    @Published public private(set) var hasUpdates = false
    @Published public private(set) var simplificationStates: [String: String] = [:]
    @Published private var simplified: [String: NewsShortVersion] = [:]
    @Published public private(set) var popupStatus = "Scheduled cards are off."
    public var popupVisible = false
    public var popupAllowed: () -> Bool = { true }
    public var presentPopup: ((NewsPopupItem) -> Bool)?
    private var popupPreparing = false
    private var popupRevision = UUID()
    private var popupRetry: Date?
    public var popupPreferences: NewsPopupPreferences { preferences.popup ?? NewsPopupPreferences() }
    public var popupsPaused: Bool { (popupPreferences.pausedUntil ?? 0) > clock().timeIntervalSince1970 }
    public var pageVisible = false
    public var learningUnits: () -> [String] = { [] }
    public var readingActive: () -> Bool = { false }
    public var deliverDigest: (([NewsArticle]) async -> Bool)?
    public var simplifyExcerpt: ((String) async throws -> String)?
    public var modelAvailable: (() -> Bool)?
    public var modelIdentity: () -> String = { "Local language model" }
    public var meaningPreservationWords: [String] = []
    public var languageInstructions = ""
    public var excludedLearningUnits: Set<String> = []
    private let directory: URL
    private let clock: () -> Date
    private let downloadOverride: ((URL) async throws -> String)?
    private let session: URLSession
    private var cache: NewsCache
    private var lastAttempt: Date?
    private var nextRetry: Date?
    private var failedRequests = 0
    private var fetchTask: Task<String, Error>?
    private var backgroundTask: Task<Void, Never>?
    private var rotation = 0
    private var generationTask: Task<String, Error>?
    private let dayFormat: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
    public init(directory: URL? = nil, clock: @escaping () -> Date = Date.init,
                download: ((URL) async throws -> String)? = nil) {
        let storageDirectory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Babelstaarnet")
        self.directory = storageDirectory
        reader = NewsReadingSupport(directory: storageDirectory)
        self.clock = clock; self.downloadOverride = download
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration, delegate: NewsRedirectDelegate(), delegateQueue: nil)
        func load<T: Decodable>(_ name: String, type: T.Type) -> T? {
            let url = storageDirectory.appendingPathComponent(name)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        preferences = NewsPreferences(); cache = NewsCache()
        preferences = load("news-preferences.json", type: NewsPreferences.self) ?? NewsPreferences()
        cache = load("news-cache.json", type: NewsCache.self) ?? NewsCache()
        preferences.topic = min(7, max(0, preferences.topic)); preferences.digestHour = min(20, max(9, preferences.digestHour))
        if !preferences.enabled { preferences.background = false; preferences.notify = false }
        if !preferences.background { preferences.notify = false; preferences.popup?.enabled = false }
        if var popup = preferences.popup {
            popup.intervalMinutes = [60, 120, 240].contains(popup.intervalMinutes) ? popup.intervalMinutes : 120
            popup.shown = min(3, max(0, popup.shown)); popup.ids = Array(popup.ids.filter { $0.count < 512 }.suffix(100))
            if let at = popup.lastShown, !at.isFinite || at > clock().timeIntervalSince1970 { popup.lastShown = clock().timeIntervalSince1970 }
            if let until = popup.pausedUntil, !until.isFinite || until > clock().timeIntervalSince1970 + 86400 { popup.pausedUntil = nil }
            preferences.popup = popup
        }
        cache.articles = Array(cache.articles.filter(\.valid).prefix(256))
        if !cache.fetched.isFinite || cache.fetched < 0 || cache.fetched > clock().timeIntervalSince1970 + 3600 { cache.fetched = 0 }
        selectCards()
        reader.beforeHelp = { [weak self] in self?.cancelGeneration() }
        simplified = Dictionary(uniqueKeysWithValues: (cache.shortVersions ?? [:]).filter {
            $0.key.count < 1000 && !$0.value.text.isEmpty && $0.value.text.utf8.count <= 3000 && $0.value.model.count <= 200 && $0.value.created.isFinite
        }.sorted { $0.key < $1.key }.prefix(64).map { ($0.key, $0.value) })
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(preferences).write(to: directory.appendingPathComponent("news-preferences.json"), options: .atomic)
            try JSONEncoder().encode(cache).write(to: directory.appendingPathComponent("news-cache.json"), options: .atomic)
        } catch { status = "News changes could not be saved: \(error.localizedDescription)" }
    }
    public func configure(enabled: Bool, background: Bool, notify: Bool, topic: Int, hour: Int) {
        let changedTopic = preferences.topic != topic
        preferences.enabled = enabled; preferences.background = enabled && background; preferences.notify = enabled && background && notify
        preferences.topic = min(7, max(0, topic)); preferences.digestHour = min(20, max(9, hour))
        if !enabled || changedTopic { fetchTask?.cancel(); cancelGeneration(); rotation = 0 }
        if changedTopic { nextRetry = nil; failedRequests = 0 }
        if !enabled { status = "News is off. Cached articles remain available offline." }
        if !enabled || !background || notify { preferences.popup?.enabled = false; popupRevision = UUID() }
        if changedTopic { popupRevision = UUID() }
        save(); selectCards()
    }
    public func refresh(manual: Bool = false, background: Bool = false) async {
        guard !busy, !(background && pageVisible) else { return }
        let now = clock()
        if !manual, let nextRetry, now < nextRetry { return }
        let age = cache.topic == preferences.topic && cache.fetched > 0 ? now.timeIntervalSince1970 - cache.fetched : -1
        guard SharedPolicy.fetch(enabled: preferences.enabled, background: preferences.background, backgroundRequest: background,
            manual: manual, attempt: lastAttempt.map { now.timeIntervalSince($0) } ?? -1, success: age) else {
            if manual && preferences.enabled, let lastAttempt, now.timeIntervalSince(lastAttempt) < 60 { status = "Recently refreshed. Try again in a minute." }; return
        }
        lastAttempt = now; busy = true; status = "Fetching public headlines from DR…"
        let topic = preferences.topic, url = SharedPolicy.feedURL(topic: preferences.topic)
        let task: Task<String, Error>
        if let downloadOverride { task = Task { try await downloadOverride(url) } }
        else {
            let session = session
            task = Task {
                var request = URLRequest(url: url); request.setValue("Babelstaarnet/0.6.3", forHTTPHeaderField: "User-Agent")
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.expectedContentLength <= 1_000_000 else { throw URLError(.badServerResponse) }
                var data = Data()
                for try await byte in bytes { try Task.checkCancellation(); guard data.count < 1_000_000 else { throw URLError(.dataLengthExceedsMaximum) }; data.append(byte) }
                guard let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }; return text
            }
        }
        fetchTask = task
        defer { fetchTask = nil; busy = false }
        do {
            let xml = try await task.value
            guard !task.isCancelled, preferences.enabled, preferences.topic == topic else { return }
            let articles = try Self.parseFeed(xml, topic: topic)
            guard !articles.isEmpty else { throw URLError(.cannotParseResponse) }
            cache.articles = articles; cache.fetched = now.timeIntervalSince1970; cache.topic = topic; rotation = 0
            failedRequests = 0; nextRetry = nil
            save()
            if cards.isEmpty || manual || !pageVisible { selectCards() } else { hasUpdates = true }
            status = "Updated from DR · " + now.formatted(date: .abbreviated, time: .shortened)
        } catch is CancellationError { }
        catch { if preferences.enabled && !task.isCancelled {
            failedRequests = min(16, failedRequests + 1); nextRetry = clock().addingTimeInterval(SharedPolicy.retryDelay(failures: failedRequests))
            status = "News could not be updated. Cached content remains available. " + error.localizedDescription
        } }
    }
    public func nextGroup() { rotation += 3; hasUpdates = false; selectCards() }
    public func acceptUpdates() { rotation = 0; hasUpdates = false; selectCards() }
    public func setBookPage(_ page: Int) { preferences.lastBookPage = min(1, max(0, page)); save() }
    public func simplifiedText(for article: NewsArticle) -> String? { simplified[excerptKey(article)]?.text }
    public func simplifiedModel(for article: NewsArticle) -> String? { simplified[excerptKey(article)]?.model }
    public func simplificationState(for article: NewsArticle) -> String? { simplificationStates[excerptKey(article)] }
    private func excerptText(_ article: NewsArticle) -> String { article.summary.isEmpty ? article.title : article.summary }
    private func excerptKey(_ article: NewsArticle) -> String {
        // Source text, rather than a URL alone, versions the cached derivative.
        article.id + ":v1:" + SHA256.hash(data: Data((excerptText(article) + "\u{1f}" + SharedPolicy.rewritePrompt + "\u{1f}" + languageInstructions + "\u{1f}" + meaningPreservationWords.joined(separator: "\n")).utf8)).map { String(format: "%02X", $0) }.joined()
    }
    public func simplify(_ article: NewsArticle) async {
        let key = excerptKey(article)
        if simplified[key] != nil { return }
        let decision = SharedPolicy.rewrite(sourceAllows: SharedPolicy.sourceCapability(2), textPresent: !excerptText(article).isEmpty, modelInstalled: modelAvailable?() ?? (simplifyExcerpt != nil), reading: readingActive())
        guard decision == 1 else {
            simplificationStates[key] = decision == 2 ? "Pause screen reading to simplify this excerpt. The original remains available." : "Install the optional local language model to simplify RSS excerpts."
            return
        }
        guard generationTask == nil, let simplifyExcerpt else { return }
        simplificationStates[key] = "Simplifying this RSS excerpt locally…"
        let task = Task { try await simplifyExcerpt(excerptText(article)) }; generationTask = task
        let timeout = Task { try? await Task.sleep(for: .seconds(90)); if !Task.isCancelled { task.cancel() } }
        defer { timeout.cancel(); generationTask = nil }
        do {
            let text = try await task.value
            guard !task.isCancelled else { throw CancellationError() }
            guard SharedPolicy.summaryValid(source: excerptText(article), summary: text, preservationWords: meaningPreservationWords) else { throw URLError(.cannotDecodeContentData) }
            let version = NewsShortVersion(text: text, model: modelIdentity(), created: clock().timeIntervalSince1970)
            simplified[key] = version; simplificationStates.removeValue(forKey: key)
            if simplified.count > 64 { simplified = [key: version] }
            cache.shortVersions = simplified; save()
        } catch { simplificationStates[key] = "Short version unavailable; the original excerpt remains available." }
    }
    public func cancelGeneration() { generationTask?.cancel() }
    public func markSeen(_ article: NewsArticle) {
        let now = clock().timeIntervalSince1970
        cache.seen[article.id] = now; cache.seenTitles[article.title] = now
        cache.seen = Dictionary(uniqueKeysWithValues: cache.seen.filter { now - $0.value <= 604800 }.sorted { $0.value > $1.value }.prefix(256).map { ($0.key, $0.value) })
        cache.seenTitles = Dictionary(uniqueKeysWithValues: cache.seenTitles.filter { now - $0.value <= 604800 }.sorted { $0.value > $1.value }.prefix(100).map { ($0.key, $0.value) })
        save(); selectCards()
    }
    public func selectCards() {
        let now = clock().timeIntervalSince1970
        let units = Array(Set(learningUnits().map { $0.precomposedStringWithCanonicalMapping.lowercased() }.filter { !excludedLearningUnits.contains($0) }).sorted().prefix(200))
        var ranked = cache.articles.filter { $0.valid && $0.topic == preferences.topic }.map { article -> NewsCard in
            let matches = Array(units.filter { SharedPolicy.contains(article.title + " " + article.summary, unit: $0) }.prefix(5))
            let seen = cache.seen[article.id].map { now - $0 <= 604800 } == true || cache.seenTitles.contains { now - $0.value <= 604800 && SharedPolicy.sameStory(article.title, $0.key) }
            return NewsCard(article: article, matches: matches, score: SharedPolicy.score(age: (now - article.published) / 3600, interest: 0.5, matches: Double(matches.count) * 0.25, seen: seen))
        }.filter { $0.score >= 0 }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.article.published != $1.article.published { return $0.article.published > $1.article.published }
            return $0.id < $1.id
        }
        var unique: [NewsCard] = []
        for item in ranked where !unique.contains(where: { SharedPolicy.sameStory($0.article.title, item.article.title) }) { unique.append(item) }
        let fresh = unique.filter { now - $0.article.published <= 172800 }; if fresh.count >= 3 { ranked = fresh } else { ranked = unique }
        if rotation >= ranked.count { rotation = 0 }
        cards = Array(ranked.dropFirst(rotation).prefix(3))
        if cache.fetched > 0 && !busy { status = "Cached on " + Date(timeIntervalSince1970: cache.fetched).formatted(date: .abbreviated, time: .shortened) + (preferences.enabled ? " · matching stays on this Mac" : " · news is off") }
    }
    public func makePopupReader() -> NewsReadingSupport {
        let popupReader = NewsReadingSupport(directory: directory)
        popupReader.translate = reader.translate; popupReader.cachedWordMeaning = reader.cachedWordMeaning
        popupReader.knowledgeLevel = reader.knowledgeLevel; popupReader.speak = reader.speak
        popupReader.saveWord = reader.saveWord; popupReader.beforeHelp = reader.beforeHelp
        return popupReader
    }
    public func configurePopups(enabled: Bool, interval: Int) {
        var popup = popupPreferences
        let allowed = enabled && preferences.enabled && preferences.background
        if allowed && (!popup.enabled || popup.intervalMinutes != interval) { popup.lastShown = clock().timeIntervalSince1970 }
        popup.enabled = allowed; popup.intervalMinutes = [60, 120, 240].contains(interval) ? interval : 120
        if allowed { preferences.notify = false } else { cancelGeneration() }
        preferences.popup = popup; popupRevision = UUID(); popupRetry = nil
        popupStatus = allowed ? "Scheduled cards are on. The first card follows your chosen interval." : "Scheduled cards are off."
        save()
    }
    public func pausePopupsForToday(_ paused: Bool) {
        var popup = popupPreferences
        popup.pausedUntil = paused ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: clock()))!.timeIntervalSince1970 : nil
        preferences.popup = popup; popupRevision = UUID(); cancelGeneration(); save()
        popupStatus = paused ? "News cards are paused for today." : "News cards resumed."
    }
    public func popupDue() -> Bool {
        let now = clock(), popup = popupPreferences
        dayFormat.timeZone = .autoupdatingCurrent
        return SharedPolicy.newsPopupDue(enabled: preferences.enabled, background: preferences.background, optedIn: popup.enabled,
            blocked: readingActive() || pageVisible || popupVisible || popupsPaused || !popupAllowed() || (popupRetry.map { now < $0 } ?? false),
            hour: Calendar.current.component(.hour, from: now), elapsed: now.timeIntervalSince1970 - (popup.lastShown ?? now.timeIntervalSince1970),
            interval: popup.intervalMinutes, shown: popup.day == dayFormat.string(from: now) ? popup.shown : 0, fresh: popupCandidates.count)
    }
    private var popupCandidates: [NewsArticle] { cards.map(\.article).filter { !(popupPreferences.ids).contains($0.id) && clock().timeIntervalSince1970 - $0.published >= 0 && clock().timeIntervalSince1970 - $0.published <= 172800 } }
    /// Called by the app's minute tick. No window or model is opened by the service itself.
    public func tickPopup(preview: Bool = false) async {
        func eligible() -> Bool { preview ? preferences.enabled && !readingActive() && !popupVisible && popupAllowed() : popupDue() }
        guard !popupPreparing, eligible(), let candidate = (preview ? cards.map(\.article) : popupCandidates).first, let presentPopup else {
            if preview { popupStatus = "Pause screen reading, enable DR news, and refresh news before trying a card." }; return
        }
        guard modelAvailable?() ?? (simplifyExcerpt != nil) else { popupStatus = "Install local AI in Settings to receive adapted news cards."; return }
        popupPreparing = true; let revision = popupRevision
        defer { popupPreparing = false }
        await simplify(candidate)
        guard popupRevision == revision, eligible() else { return }
        guard let text = simplifiedText(for: candidate), let model = simplifiedModel(for: candidate) else {
            popupStatus = "Adapted card unavailable. Will try again later; the original remains in Word Book."
            popupRetry = clock().addingTimeInterval(600); return
        }
        // Recheck after local generation: turning off or pausing must win over a late result.
        if presentPopup(NewsPopupItem(original: candidate, text: text, model: model, preview: preview)) {
            var popup = popupPreferences; let now = clock(); let day = dayFormat.string(from: now)
            popup.shown = (popup.day == day ? popup.shown : 0) + 1; popup.day = day; popup.lastShown = now.timeIntervalSince1970
            popup.ids = Array((popup.ids + [candidate.id]).suffix(100)); preferences.popup = popup
            popupStatus = "A short Danish news card was shown."; save()
        }
    }
    public func startBackground() {
        guard backgroundTask == nil else { return }
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60)); guard let self, !Task.isCancelled else { return }
                await self.refresh(background: true)
                await self.tickPopup()
                let now = self.clock(), hour = Calendar.current.component(.hour, from: now)
                self.dayFormat.timeZone = .autoupdatingCurrent
                let day = self.dayFormat.string(from: now)
                let candidates = self.cards.map(\.article).filter { !(self.preferences.lastDigestIds ?? []).contains($0.id) && now.timeIntervalSince1970 - $0.published >= 0 && now.timeIntervalSince1970 - $0.published <= 604800 }
                guard SharedPolicy.digest(enabled: self.preferences.enabled, background: self.preferences.background,
                    notify: self.preferences.notify, permitted: self.deliverDigest != nil, reading: self.readingActive() || self.pageVisible,
                    quiet: hour < 9 || hour >= 21 || hour != self.preferences.digestHour,
                    sent: self.preferences.lastDigestDay == day ? 1 : 0, fresh: candidates.count) else { continue }
                if await self.deliverDigest?(candidates) == true {
                    self.preferences.lastDigestDay = day
                    self.preferences.lastDigestIds = Array(((self.preferences.lastDigestIds ?? []) + candidates.prefix(1).map(\.id)).suffix(100))
                    self.save()
                }
            }
        }
    }
    public func stop() { popupRevision = UUID(); fetchTask?.cancel(); cancelGeneration(); reader.cancel(); backgroundTask?.cancel(); backgroundTask = nil }
    public static func parseFeed(_ xml: String, topic: Int) throws -> [NewsArticle] {
        guard xml.utf8.count <= 1_000_000, !xml.localizedCaseInsensitiveContains("<!DOCTYPE"), !xml.localizedCaseInsensitiveContains("<!ENTITY") else { throw URLError(.cannotParseResponse) }
        let parser = XMLParser(data: Data(xml.utf8)); parser.shouldResolveExternalEntities = false
        let delegate = FeedParser(topic: topic); parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        return delegate.articles
    }
}

private final class FeedParser: NSObject, XMLParserDelegate {
    let topic: Int
    var articles: [NewsArticle] = []
    var fields: [String: String] = [:]
    var capture: String?
    var inItem = false
    private let date: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"; return f }()
    init(topic: Int) { self.topic = topic }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "item" { inItem = true; fields = [:] }
        if inItem && ["title", "description", "link", "guid", "pubDate"].contains(elementName) { capture = elementName; fields[elementName] = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if let capture { fields[capture, default: ""] += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if let text = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: text) } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if capture == elementName { capture = nil }
        if elementName == "item" {
            inItem = false
            guard articles.count < 128, let published = date.date(from: fields["pubDate", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            let url = fields["link", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            let id = fields["guid", default: url]
            let item = NewsArticle(id: id.isEmpty ? url : id, title: plain(fields["title", default: ""], limit: 350),
                summary: plain(fields["description", default: ""], limit: 3000), url: url, published: published.timeIntervalSince1970, topic: topic)
            if item.valid && !articles.contains(where: { $0.url == item.url }) { articles.append(item) }
        }
    }
    private func plain(_ value: String, limit: Int) -> String {
        var value = value
        for (a,b) in [("&amp;","&"),("&quot;","\""),("&#39;","'"),("&apos;","'"),("&lt;","<"),("&gt;",">"),("&nbsp;"," ")] { value = value.replacingOccurrences(of: a, with: b) }
        return String(value.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"\s+([.,;:!?])"#, with: "$1", options: .regularExpression).prefix(limit))
    }
}
