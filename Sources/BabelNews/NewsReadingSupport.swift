import BabelCore
import Combine
import CryptoKit
import Foundation

public struct NewsEnglish: Codable, Sendable {
    public let parts: [String]
    let created: Double
}
public struct NewsWordHelp: Sendable {
    public let articleKey: String
    public let word: String
    public var meaning: String
    public var status: String
    public var saved = false
}
private struct NewsReadingCache: Codable {
    var english: [String: NewsEnglish] = [:]
    var showEnglish: Bool? = true
}

/// Reading support for public source text. It has no network or screen-capture API.
@MainActor public final class NewsReadingSupport: ObservableObject {
    @Published public private(set) var meanings: [String: NewsEnglish] = [:]
    @Published public private(set) var states: [String: String] = [:]
    @Published public private(set) var selected: NewsWordHelp?
    @Published public private(set) var showEnglish = true
    public var translate: (([String]) async throws -> [String])?
    public var cachedWordMeaning: (String) -> String? = { _ in nil }
    public var beforeHelp: (() -> Void)?
    public var speak: ((String) -> Void)?
    public var saveWord: ((String, String, String) -> Void)?
    private let path: URL
    private var owners: [String: UUID] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var wordTask: Task<Void, Never>?
    private var revealed = Set<String>()
    public init(directory: URL) {
        path = directory.appendingPathComponent("news-reading.json")
        if let size = try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
           let data = try? Data(contentsOf: path), let cache = try? JSONDecoder().decode(NewsReadingCache.self, from: data) {
            showEnglish = cache.showEnglish ?? true
            meanings = Dictionary(uniqueKeysWithValues: cache.english.filter { $0.key.count < 1000 && $0.value.created.isFinite && (1...2).contains($0.value.parts.count) && $0.value.parts.allSatisfy { !$0.isEmpty && $0.utf8.count <= 18000 } }.sorted { $0.value.created > $1.value.created }.prefix(32).map { ($0.key, $0.value) })
        }
    }
    public static func sourceParts(_ article: NewsArticle) -> [String] { [article.title] + (article.summary.isEmpty ? [] : [article.summary]) }
    public static func key(_ article: NewsArticle) -> String {
        article.id + ":da-en-v1:" + SHA256.hash(data: Data(sourceParts(article).joined(separator: "\u{1f}").utf8)).map { String(format: "%02X", $0) }.joined()
    }
    public func meaning(_ article: NewsArticle) -> NewsEnglish? { guard let value = meanings[Self.key(article)], value.parts.count == Self.sourceParts(article).count else { return nil }; return value }
    public func state(_ article: NewsArticle) -> String? { states[Self.key(article)] }
    public func isVisible(_ article: NewsArticle) -> Bool { showEnglish || revealed.contains(Self.key(article)) }
    public func setEnglish(_ enabled: Bool) { showEnglish = enabled; revealed.removeAll(); if !enabled { cancel() }; persist() }
    public func prepare(_ article: NewsArticle, requested: Bool = false) async {
        let key = Self.key(article)
        if requested { beforeHelp?(); revealed.insert(key); objectWillChange.send() }
        let decision = SharedPolicy.readingHelp(requested: requested, english: showEnglish, cached: meaning(article) != nil, available: translate != nil)
        guard decision > 1 else { return }
        guard decision == 2, let translate else { states[key] = "Set up local translation in Settings to read this with English support."; return }
        if let task = tasks[key] { await task.value; return }
        let owner = UUID(); owners[key] = owner
        states[key] = "Preparing English on this device…"
        let task = Task(priority: .utility) { [weak self] in
            do {
                let texts = Self.sourceParts(article), translated = try await translate(texts)
                try Task.checkCancellation()
                guard translated.count == texts.count, translated.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 18000 }) else { throw URLError(.cannotDecodeContentData) }
                guard let self, self.owners[key] == owner else { return }
                self.meanings[key] = NewsEnglish(parts: translated, created: Date().timeIntervalSince1970)
                if self.meanings.count > 32, let oldest = self.meanings.filter({ $0.key != key }).min(by: { $0.value.created < $1.value.created })?.key { self.meanings.removeValue(forKey: oldest) }
                self.states.removeValue(forKey: key); self.persist()
            } catch is CancellationError { if self?.owners[key] == owner { self?.states.removeValue(forKey: key) } }
            catch { if self?.owners[key] == owner { self?.states[key] = "English support is unavailable. Check local translation in Settings, then try again. " + error.localizedDescription } }
            if self?.owners[key] == owner { self?.tasks.removeValue(forKey: key); self?.owners.removeValue(forKey: key) }
        }
        tasks[key] = task; await task.value
    }
    public func lookup(_ word: String, article: NewsArticle) async {
        // Lookup is explicit help, never evidence that the whole story was understood.
        beforeHelp?(); wordTask?.cancel()
        let key = Self.key(article), identity = UUID()
        selectionID = identity
        let cached = cachedWordMeaning(word)
        selected = NewsWordHelp(articleKey: key, word: word, meaning: cached ?? "", status: cached == nil ? "Looking up on this device…" : "Word meaning · use the English sentence for context")
        guard cached == nil, let translate else { if cached == nil { selected?.status = "Set up local translation in Settings for word meanings." }; return }
        let task = Task(priority: .userInitiated) { [weak self] in
            do {
                let result = try await translate([word]); try Task.checkCancellation()
                guard self?.selectionID == identity else { return }
                self?.selected?.meaning = result.first ?? ""
                self?.selected?.status = "Word meaning · use the English sentence for context"
            } catch { if self?.selectionID == identity { self?.selected?.status = "Word meaning unavailable. The English sentence above can help." } }
        }
        wordTask = task; await task.value
    }
    private var selectionID = UUID()
    public func saveSelection(article: NewsArticle) {
        guard var value = selected, value.articleKey == Self.key(article), !value.meaning.isEmpty, let saveWord else { return }
        saveWord(value.word, value.meaning, Self.sourceParts(article).joined(separator: " "))
        value.saved = true; selected = value
    }
    public func cancel() { for task in tasks.values { task.cancel() }; tasks.removeAll(); owners.removeAll(); states.removeAll(); wordTask?.cancel(); selectionID = UUID(); selected = nil }
    private func persist() {
        do { try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(NewsReadingCache(english: meanings, showEnglish: showEnglish)).write(to: path, options: .atomic) }
        catch { /* Reading still works if a public-text cache cannot be written. */ }
    }
    /// Split only on whitespace: numbers and punctuation stay in the displayed source.
    public static func pieces(_ text: String) -> [String] { text.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
    private static let wordPattern = try! NSRegularExpression(pattern: #"[\p{L}\p{M}]+(?:['’\-][\p{L}\p{M}]+)*"#)
    public static func word(_ piece: String) -> String? {
        guard let match = wordPattern.firstMatch(in: piece, range: NSRange(piece.startIndex..., in: piece)), let range = Range(match.range, in: piece) else { return nil }
        return String(piece[range])
    }
}
