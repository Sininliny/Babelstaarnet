import BabelCore
import Darwin
import Foundation
import Synchronization

public enum ArgosTranslationError: LocalizedError {
    case unavailable
    case executionFailed(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Argos Translate or the required local language model is not installed."
        case let .executionFailed(message):
            return "Argos Translate failed: \(message)"
        case .invalidResponse:
            return "Argos Translate returned an invalid response."
        }
    }
}

public actor ArgosTranslationService {
    private let languages: LanguagePair
    private let pythonPathOverride: String?
    private let bridgeURLOverride: URL?
    private let responseTimeout: TimeInterval

    public init(languages: LanguagePair) {
        self.languages = languages
        pythonPathOverride = nil
        bridgeURLOverride = nil
        responseTimeout = 30
    }

    /// A controlled worker for checks, without changing shipped engine lookup.
    init(
        languages: LanguagePair,
        pythonPath: String,
        bridgeURL: URL,
        responseTimeout: TimeInterval
    ) {
        self.languages = languages
        pythonPathOverride = pythonPath
        bridgeURLOverride = bridgeURL
        self.responseTimeout = responseTimeout
    }

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var recentErrors = ArgosWorkerErrors()
    private var responseBuffer = Data()
    private var activeLanguagePair: (source: String, target: String)?

    public func isReady(keepWarm: Bool = true) async -> Bool {
        let source = languages.source.code
        let target = languages.target.code
        do {
            _ = try request(
                texts: [],
                source: source,
                target: target
            )
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
        do {
            _ = try request(
                texts: [],
                source: languages.source.code,
                target: languages.target.code
            )
        } catch {
            resetServer()
        }
    }

    public func isWordBridgeReady(keepWarm: Bool = true) async -> Bool {
        do {
            _ = try requestDefinitions(words: [])
            if !keepWarm {
                resetServer()
            }
            return true
        } catch {
            resetServer()
            return false
        }
    }

    /// Warms the reverse direction, which is the one the word bridge asks in.
    public func warmUpWordBridge() async {
        do {
            _ = try request(
                texts: [],
                source: languages.target.code,
                target: languages.source.code
            )
        } catch {
            resetServer()
        }
    }

    /// Explains words of the target language in the language being learned,
    /// which is the reverse of the reading direction.
    public func explainTargetWordsInSourceLanguage(
        _ words: [String]
    ) async throws -> [String] {
        guard !words.isEmpty else {
            return []
        }
        do {
            return try requestDefinitions(words: words)
        } catch {
            resetServer()
            return try requestDefinitions(words: words)
        }
    }

    public func translate(_ texts: [String]) async throws -> [String] {
        guard !texts.isEmpty else {
            return []
        }
        let source = languages.source.code
        let target = languages.target.code

        do {
            return try request(
                texts: texts,
                source: source,
                target: target
            )
        } catch {
            resetServer()
            return try request(
                texts: texts,
                source: source,
                target: target
            )
        }
    }

    public func shutdown() {
        resetServer()
    }

    private func request(
        texts: [String],
        source: String,
        target: String
    ) throws -> [String] {
        try ensureServer(source: source, target: target)
        guard let input, let output else {
            throw ArgosTranslationError.unavailable
        }

        var requestData = try JSONEncoder().encode(
            BatchRequest(texts: texts)
        )
        requestData.append(0x0A)
        try input.write(contentsOf: requestData)

        let responseData = try readResponseLine(from: output)
        guard let response = try? JSONDecoder().decode(
            BatchResponse.self,
            from: responseData
        ), response.translations.count == texts.count else {
            throw ArgosTranslationError.invalidResponse
        }
        return response.translations
    }

    private func requestDefinitions(words: [String]) throws -> [String] {
        try ensureServer(
            source: languages.target.code,
            target: languages.source.code
        )
        guard let input, let output else {
            throw ArgosTranslationError.unavailable
        }

        var requestData = try JSONEncoder().encode(
            WordBridgeRequest(defineWords: words)
        )
        requestData.append(0x0A)
        try input.write(contentsOf: requestData)

        let responseData = try readResponseLine(from: output)
        guard let response = try? JSONDecoder().decode(
            BatchResponse.self,
            from: responseData
        ), response.translations.count == words.count else {
            throw ArgosTranslationError.invalidResponse
        }
        return response.translations
    }

    private func ensureServer(
        source: String,
        target: String
    ) throws {
        try Task.checkCancellation()
        if let process,
           process.isRunning,
           activeLanguagePair?.source == source,
           activeLanguagePair?.target == target {
            return
        }
        resetServer()

        guard let pythonURL = pythonPathOverride.map(URL.init(fileURLWithPath:))
                ?? Self.pythonURL,
              let bridgeURL = bridgeURLOverride ?? Self.bridgeURL else {
            throw ArgosTranslationError.unavailable
        }

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            bridgeURL.path,
            "--server",
            "--source", source,
            "--target", target
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["ARGOS_DEVICE_TYPE"] = "cpu"
        environment["ARGOS_CHUNK_TYPE"] = "MINISBD"
        environment["PYTHONUNBUFFERED"] = "1"
        Self.configureDataDirectories(in: &environment)
        environment["NLTK_DATA"] = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Babelstaarnet/WordWise"
            ).path
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Python can emit enough startup warnings to fill stderr before it
        // reads stdin. Drain it independently of the response, retaining only
        // a bounded tail for diagnostics.
        let recentErrors = ArgosWorkerErrors()
        self.recentErrors = recentErrors
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            recentErrors.append(data)
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
        }

        do {
            try process.run()
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw ArgosTranslationError.unavailable
        }

        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        errors = errorPipe.fileHandleForReading
        activeLanguagePair = (source, target)
    }

    private func readResponseLine(
        from output: FileHandle
    ) throws -> Data {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(responseTimeout))
        while true {
            try Task.checkCancellation()
            if let newline = responseBuffer.firstIndex(of: 0x0A) {
                let line = responseBuffer[..<newline]
                responseBuffer.removeSubrange(...newline)
                return Data(line)
            }

            guard clock.now < deadline else {
                throw ArgosTranslationError.executionFailed(
                    "translation worker timed out"
                )
            }
            let remaining = clock.now.duration(to: deadline).components
            let milliseconds = remaining.seconds * 1_000
                + remaining.attoseconds / 1_000_000_000_000_000
            var descriptor = pollfd(
                fd: output.fileDescriptor,
                events: Int16(POLLIN),
                revents: 0
            )
            // Poll in short intervals so cancellation can also stop a worker
            // that remains alive without sending a complete JSON line.
            let status = poll(
                &descriptor,
                1,
                Int32(max(1, min(250, milliseconds)))
            )
            if status < 0 {
                if errno == EINTR {
                    continue
                }
                throw ArgosTranslationError.executionFailed(
                    "could not read translation worker response"
                )
            }
            if status == 0 {
                continue
            }
            guard descriptor.revents & Int16(POLLNVAL) == 0 else {
                throw ArgosTranslationError.executionFailed(
                    "translation worker output closed"
                )
            }
            let chunk = output.availableData
            guard !chunk.isEmpty else {
                let message = recentErrors.text
                throw ArgosTranslationError.executionFailed(
                    message.isEmpty ? "translation worker stopped" : message
                )
            }
            responseBuffer.append(chunk)
        }
    }

    private func resetServer() {
        if process?.isRunning == true {
            process?.terminate()
        }
        errors?.readabilityHandler = nil
        try? input?.close()
        try? output?.close()
        try? errors?.close()
        process = nil
        input = nil
        output = nil
        errors = nil
        responseBuffer.removeAll(keepingCapacity: true)
        activeLanguagePair = nil
    }

    /// The bundled bridge script, plus the checkout's copy when this is a
    /// debug build.
    ///
    /// The working-directory copy is there so the executable can be run
    /// straight out of the repository during development. It resolves a
    /// relative path against whatever directory the process happens to have
    /// been started in, which is a fine convenience for a build only a
    /// developer runs and a way to execute someone else's script in a build
    /// handed to readers. A shipped app never needs it: the script is inside
    /// the bundle.
    private static var bridgeURL: URL? {
        var candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("LocalEngines/argos_bridge.py")
        ].compactMap { $0 }
#if DEBUG
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/LocalEngines/argos_bridge.py")
        )
#endif
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    /// Where the interpreter is looked for, as a closed list, for the reason
    /// given on `InstalledEngineLocations`. This one is handed the recognized
    /// text rather than the capture, which is the same secret one step later.
    private static var pythonURL: URL? {
        InstalledEngineLocations.python
            .first(where: FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }

    private static func configureDataDirectories(
        in environment: inout [String: String]
    ) {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Babelstaarnet/Argos"
            )
        environment["XDG_DATA_HOME"] = root
            .appendingPathComponent("data").path
        environment["XDG_CONFIG_HOME"] = root
            .appendingPathComponent("config").path
        environment["XDG_CACHE_HOME"] = root
            .appendingPathComponent("cache").path
    }
}

private final class ArgosWorkerErrors: Sendable {
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

    var text: String {
        buffer.withLock {
            String(decoding: $0, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private struct BatchRequest: Encodable {
    public let texts: [String]
}

private struct BatchResponse: Decodable {
    public let translations: [String]
}

private struct WordBridgeRequest: Encodable {
    public let defineWords: [String]

    enum CodingKeys: String, CodingKey {
        case defineWords = "define_words"
    }
}
