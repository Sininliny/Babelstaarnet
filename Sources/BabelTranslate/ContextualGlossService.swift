import BabelCore
import Foundation
import Synchronization

public enum ContextualGlossError: LocalizedError {
    case unavailable
    case executionFailed(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The local language model for contextual glosses is not installed."
        case let .executionFailed(message):
            return "The contextual glosser failed: \(message)"
        case .invalidResponse:
            return "The contextual glosser returned an invalid response."
        }
    }
}

/// What a sentence's words mean in that sentence, and what the word under the
/// pointer means, with its dictionary form and a short explanation in the
/// language being learned.
public struct ContextualGloss: Equatable, Sendable {
    public struct FocusedWord: Equatable, Sendable {
        public let gloss: String
        public let lemma: String
        public let explanation: String

        public init(gloss: String, lemma: String, explanation: String) {
            self.gloss = gloss
            self.lemma = lemma
            self.explanation = explanation
        }
    }

    /// One per requested word, in the order asked. Empty wherever the model's
    /// answer could not be tied to the word it was asked about, which the
    /// caller treats as no answer rather than as an empty one.
    public let glosses: [String]
    public let focus: FocusedWord?

    public init(glosses: [String], focus: FocusedWord?) {
        self.glosses = glosses
        self.focus = focus
    }
}

/// A local language model, asked for the sense each word has in its sentence.
///
/// Word-at-a-time translation cannot know that "får" in "Han får en ny bil"
/// is "gets" and not "sheep": nothing it is handed says so. Measured on 31
/// Danish words whose meaning depends on the sentence, one word at a time got
/// 6 right; given the sentence, a 4B model running on the Mac got 29.
///
/// The worker is the same kind of process as the Argos one — a Python script
/// in the managed environment, speaking one JSON line each way over pipes — and
/// makes no network connection: it is started with every Hugging Face network
/// switch off and loads its model from a directory, never by name.
public actor ContextualGlossService {
    private let prompts: ContextualGlossPrompts?
    private let pythonPath: String
    private let modelDirectory: URL

    public init(language: SourceLanguage) {
        self.init(
            language: language,
            pythonPath: InstalledEngineLocations.managedPython,
            modelDirectory: InstalledEngineLocations.contextualGlossModel
        )
    }

    /// For the runtime check, which measures a model before it is installed.
    /// Internal, so nothing the app ships can be pointed anywhere but the
    /// closed list in `InstalledEngineLocations`.
    init(
        language: SourceLanguage,
        pythonPath: String,
        modelDirectory: URL
    ) {
        self.prompts = language.contextualGlossPrompts
        self.pythonPath = pythonPath
        self.modelDirectory = modelDirectory
    }

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var responseBuffer = Data()
    private let recentErrors = RecentOutput()

    /// Whether everything the worker needs is on disk.
    ///
    /// Deliberately not a readiness check: starting the worker loads several
    /// gigabytes of weights, which is a cost to pay when reading starts and
    /// not when the app launches or Settings opens.
    public nonisolated var isInstalled: Bool {
        let fileManager = FileManager.default
        let model = modelDirectory
        return prompts != nil
            && fileManager.isExecutableFile(atPath: pythonPath)
            && Self.bridgeURL != nil
            && fileManager.fileExists(
                atPath: model.appendingPathComponent("config.json").path
            )
            && fileManager.fileExists(
                atPath: model.appendingPathComponent("model.safetensors").path
            )
    }

    public func isReady(keepWarm: Bool = true) async -> Bool {
        do {
            _ = try request(sentence: "", words: [], focus: nil)
            if !keepWarm {
                resetServer()
            }
            return true
        } catch {
            resetServer()
            return false
        }
    }

    public func warmUp() async {
        _ = try? request(sentence: "", words: [], focus: nil)
    }

    /// The sense of each of `words` in `sentence`, and a fuller answer for
    /// `focus` when there is one.
    public func gloss(
        sentence: String,
        words: [String],
        focus: String?
    ) async throws -> ContextualGloss {
        guard !words.isEmpty || focus != nil else {
            return ContextualGloss(glosses: [], focus: nil)
        }
        do {
            return try request(sentence: sentence, words: words, focus: focus)
        } catch {
            resetServer()
            return try request(sentence: sentence, words: words, focus: focus)
        }
    }

    public func shutdown() {
        resetServer()
    }

    private func request(
        sentence: String,
        words: [String],
        focus: String?
    ) throws -> ContextualGloss {
        try ensureServer()
        guard let input, let output else {
            throw ContextualGlossError.unavailable
        }

        var requestData = try JSONEncoder().encode(
            GlossRequest(sentence: sentence, words: words, focus: focus)
        )
        requestData.append(0x0A)
        try input.write(contentsOf: requestData)

        let responseData = try readResponseLine(from: output)
        guard let response = try? JSONDecoder().decode(
            GlossResponse.self,
            from: responseData
        ), response.glosses.count == words.count else {
            throw ContextualGlossError.invalidResponse
        }
        return ContextualGloss(
            glosses: response.glosses,
            focus: response.focus.map {
                ContextualGloss.FocusedWord(
                    gloss: $0.gloss,
                    lemma: $0.lemma,
                    explanation: $0.explanation
                )
            }
        )
    }

    private func ensureServer() throws {
        if let process, process.isRunning {
            return
        }
        resetServer()

        guard let prompts,
              isInstalled,
              let bridgeURL = Self.bridgeURL,
              let promptData = try? JSONEncoder().encode(prompts),
              let promptArgument = String(data: promptData, encoding: .utf8)
        else {
            throw ContextualGlossError.unavailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            bridgeURL.path,
            "--server",
            "--model", modelDirectory.path,
            "--prompts", promptArgument
        ]
        var environment = ProcessInfo.processInfo.environment
        // The bridge sets these itself before importing anything that reads
        // them. Setting them here as well means a bridge edited to forget
        // them still starts offline.
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        environment["TRANSFORMERS_VERBOSITY"] = "error"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONWARNINGS"] = "ignore"
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Drained as it arrives. A pipe nobody reads fills at 64 KB, and a
        // worker blocked writing a warning to a full pipe never answers the
        // request it was given.
        let recentErrors = recentErrors
        recentErrors.clear()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            recentErrors.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw ContextualGlossError.unavailable
        }

        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
    }

    private func readResponseLine(
        from output: FileHandle
    ) throws -> Data {
        while true {
            if let newline = responseBuffer.firstIndex(of: 0x0A) {
                let line = responseBuffer[..<newline]
                responseBuffer.removeSubrange(...newline)
                return Data(line)
            }

            let chunk = output.availableData
            guard !chunk.isEmpty else {
                let message = recentErrors.text
                throw ContextualGlossError.executionFailed(
                    message.isEmpty ? "glossing worker stopped" : message
                )
            }
            responseBuffer.append(chunk)
        }
    }

    private func resetServer() {
        if process?.isRunning == true {
            process?.terminate()
        }
        (process?.standardError as? Pipe)?
            .fileHandleForReading
            .readabilityHandler = nil
        try? input?.close()
        try? output?.close()
        process = nil
        input = nil
        output = nil
        responseBuffer.removeAll(keepingCapacity: true)
    }

    /// The bundled bridge script, plus the checkout's copy when this is a
    /// debug build — for the reason given on `ArgosTranslationService`.
    private static var bridgeURL: URL? {
        var candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("LocalEngines/gloss_bridge.py")
        ].compactMap { $0 }
#if DEBUG
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/LocalEngines/gloss_bridge.py")
        )
#endif
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
}

/// The last few kilobytes a worker wrote to standard error, kept so a failure
/// can say why without the pipe ever being allowed to fill.
private final class RecentOutput: Sendable {
    private let buffer = Mutex(Data())
    private let limit = 4_096

    func append(_ data: Data) {
        guard !data.isEmpty else {
            return
        }
        buffer.withLock {
            $0.append(data)
            if $0.count > limit {
                $0.removeFirst($0.count - limit)
            }
        }
    }

    func clear() {
        buffer.withLock { $0.removeAll() }
    }

    var text: String {
        buffer.withLock {
            String(decoding: $0, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private struct GlossRequest: Encodable {
    let sentence: String
    let words: [String]
    let focus: String?
}

private struct GlossResponse: Decodable {
    struct Focus: Decodable {
        let gloss: String
        let lemma: String
        let explanation: String
    }

    let glosses: [String]
    let focus: Focus?
}
