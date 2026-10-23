import BabelCore
import Combine
import Foundation
import Translation

/// Separate from screen translation: opening Word Book never starts OCR or resets its session.
@MainActor final class NewsTranslationQueue: ObservableObject {
    @Published var configuration: TranslationSession.Configuration
    var local: (([String]) async throws -> [String]?)?
    private let source: Locale.Language
    private let target: Locale.Language
    private var pending: [UUID: Request] = [:]
    private var order: [UUID] = []
    private var running = false
    private final class Request {
        let texts: [String]
        var continuation: CheckedContinuation<[String], Error>?
        init(_ texts: [String], _ continuation: CheckedContinuation<[String], Error>) { self.texts = texts; self.continuation = continuation }
        func finish(_ result: Result<[String], Error>) { continuation?.resume(with: result); continuation = nil }
    }
    init(languages: LanguagePair) {
        source = Locale.Language(identifier: languages.source.code); target = Locale.Language(identifier: languages.target.code)
        configuration = TranslationSession.Configuration(source: source, target: target)
    }
    func translate(_ texts: [String]) async throws -> [String] {
        try Task.checkCancellation()
        if let local {
            do { if let value = try await local(texts) { try Task.checkCancellation(); return value } }
            catch is CancellationError { throw CancellationError() }
            catch { /* An installed Apple pair can still supply offline help. */ }
        }
        // Never ask the reading page to download a language pack implicitly.
        guard await LanguageAvailability().status(from: source, to: target) == .installed else { throw NewsTranslationError.notInstalled }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                pending[id] = Request(texts, continuation); order.append(id)
                if !running { configuration.invalidate() }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel(id) } }
    }
    private func cancel(_ id: UUID) { pending.removeValue(forKey: id)?.finish(.failure(CancellationError())); order.removeAll { $0 == id } }
    func process(using session: TranslationSession) async {
        guard !running else { return }; running = true; defer { running = false }
        while !order.isEmpty {
            let id = order.removeFirst(); guard let request = pending[id] else { continue }
            do {
                let requests = request.texts.enumerated().map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset)) }
                let replies = try await session.translations(from: requests)
                let values = Dictionary(uniqueKeysWithValues: replies.compactMap { reply in Int(reply.clientIdentifier ?? "").map { ($0, reply.targetText) } })
                guard request.texts.indices.allSatisfy({ values[$0] != nil }) else { throw NewsTranslationError.incomplete }
                request.finish(.success(request.texts.indices.map { values[$0]! }))
            } catch { request.finish(.failure(error)) }
            pending.removeValue(forKey: id)
        }
    }
}
private enum NewsTranslationError: LocalizedError {
    case notInstalled, incomplete
    var errorDescription: String? {
        switch self {
        case .notInstalled: "Install local Danish → English translation in Settings first. No online translation was used."
        case .incomplete: "The local translator returned an incomplete answer."
        }
    }
}
