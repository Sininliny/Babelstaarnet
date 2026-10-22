import BabelCore
import Combine
import Foundation
import FoundationXML

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
public struct NewsPreferences: Codable {
    public var enabled = false
    public var background = false
    public var notify = false
    public var topic = 0
    public var digestHour = 18
    public var lastDigestDay: String?
}
private struct NewsCache: Codable {
    var fetched: Double = 0
    var topic = 0
    var articles: [NewsArticle] = []
    var seen: [String: Double] = [:]
    var seenTitles: [String: Double] = [:]
}
private final class NewsRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Native network/storage adapter. Decisions come from the same C component as Windows.
@MainActor public final class NewsService: ObservableObject {
    public static let topics = ["Latest", "Denmark", "World", "Money", "Politics", "Science", "Culture", "Sport"]
    public static let disclosure = "Connects to DR to fetch public news. Matching stays on this Mac. No word list, screenshots or learning records are uploaded. DR receives ordinary requests, including your IP address and requested URLs. Opening an original uses your browser."
    @Published public private(set) var preferences: NewsPreferences
    @Published public private(set) var cards: [NewsCard] = []
    @Published public private(set) var busy = false
    @Published public private(set) var status = "News is optional. Enable it to connect to DR."
    public var learningUnits: () -> [String] = { [] }
    public var readingActive: () -> Bool = { false }
    public var deliverDigest: (([NewsArticle]) async -> Bool)?
    private let directory: URL
    private let clock: () -> Date
    private let downloadOverride: ((URL) async throws -> String)?
    private let session: URLSession
    private var cache: NewsCache
    private var lastAttempt: Date?
    private var fetchTask: Task<String, Error>?
    private var backgroundTask: Task<Void, Never>?
    private var rotation = 0
    private let dayFormat: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
    public init(directory: URL? = nil, clock: @escaping () -> Date = Date.init,
                download: ((URL) async throws -> String)? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Babelstaarnet")
        self.clock = clock; self.downloadOverride = download
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration, delegate: NewsRedirectDelegate(), delegateQueue: nil)
        func load<T: Decodable>(_ name: String, type: T.Type) -> T? {
            let url = self.directory.appendingPathComponent(name)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        preferences = NewsPreferences(); cache = NewsCache()
        preferences = load("news-preferences.json", type: NewsPreferences.self) ?? NewsPreferences()
        cache = load("news-cache.json", type: NewsCache.self) ?? NewsCache()
        preferences.topic = min(7, max(0, preferences.topic)); preferences.digestHour = min(20, max(9, preferences.digestHour))
        if !preferences.enabled { preferences.background = false; preferences.notify = false }
        if !preferences.background { preferences.notify = false }
        cache.articles = Array(cache.articles.filter(\.valid).prefix(256))
        if !cache.fetched.isFinite || cache.fetched < 0 || cache.fetched > clock().timeIntervalSince1970 + 3600 { cache.fetched = 0 }
        selectCards()
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
        if !enabled || changedTopic { fetchTask?.cancel(); rotation = 0 }
        if !enabled { status = "News is off. Cached articles remain available offline." }
        save(); selectCards()
    }
    public func refresh(manual: Bool = false, background: Bool = false) async {
        guard !busy else { return }
        let now = clock()
        let age = cache.topic == preferences.topic && cache.fetched > 0 ? now.timeIntervalSince1970 - cache.fetched : -1
        guard SharedPolicy.fetch(enabled: preferences.enabled, background: preferences.background, backgroundRequest: background,
            manual: manual, attempt: lastAttempt.map { now.timeIntervalSince($0) } ?? -1, success: age) else { return }
        lastAttempt = now; busy = true; status = "Fetching public headlines from DR…"
        let topic = preferences.topic, url = SharedPolicy.feedURL(topic: preferences.topic)
        let task: Task<String, Error>
        if let downloadOverride { task = Task { try await downloadOverride(url) } }
        else {
            let session = session
            task = Task {
                var request = URLRequest(url: url); request.setValue("Babelstaarnet/0.5.1", forHTTPHeaderField: "User-Agent")
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
            save(); selectCards(); status = "Updated from DR · " + now.formatted(date: .abbreviated, time: .shortened)
        } catch is CancellationError { }
        catch { if preferences.enabled && !task.isCancelled { status = "News could not be updated. Cached content remains available. " + error.localizedDescription } }
    }
    public func nextGroup() { rotation += 3; selectCards() }
    public func markSeen(_ article: NewsArticle) {
        let now = clock().timeIntervalSince1970
        cache.seen[article.id] = now; cache.seenTitles[article.title] = now
        cache.seen = Dictionary(uniqueKeysWithValues: cache.seen.filter { now - $0.value <= 604800 }.sorted { $0.value > $1.value }.prefix(256).map { ($0.key, $0.value) })
        cache.seenTitles = Dictionary(uniqueKeysWithValues: cache.seenTitles.filter { now - $0.value <= 604800 }.sorted { $0.value > $1.value }.prefix(100).map { ($0.key, $0.value) })
        save(); selectCards()
    }
    public func selectCards() {
        let now = clock().timeIntervalSince1970
        let structural: Set<String> = ["og", "er", "en", "et", "at", "det", "de", "den", "der", "i", "på", "af", "til", "med", "som"]
        let units = Array(Set(learningUnits().filter { !structural.contains($0.lowercased()) }).sorted().prefix(200))
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
    public func startBackground() {
        guard backgroundTask == nil else { return }
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60)); guard let self, !Task.isCancelled else { return }
                await self.refresh(background: true)
                let now = self.clock(), hour = Calendar.current.component(.hour, from: now)
                let day = self.dayFormat.string(from: now)
                guard SharedPolicy.digest(enabled: self.preferences.enabled, background: self.preferences.background,
                    notify: self.preferences.notify, permitted: self.deliverDigest != nil, reading: self.readingActive(),
                    quiet: hour < 9 || hour >= 21 || hour != self.preferences.digestHour,
                    sent: self.preferences.lastDigestDay == day ? 1 : 0, fresh: self.cards.count) else { continue }
                if await self.deliverDigest?(self.cards.map(\.article)) == true { self.preferences.lastDigestDay = day; self.save() }
            }
        }
    }
    public func stop() { fetchTask?.cancel(); backgroundTask?.cancel(); backgroundTask = nil }
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
