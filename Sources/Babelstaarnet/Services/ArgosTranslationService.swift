import Foundation

enum ArgosTranslationError: LocalizedError {
    case unavailable
    case executionFailed(String)
    case invalidResponse

    var errorDescription: String? {
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

actor ArgosTranslationService {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var responseBuffer = Data()
    private var activeLanguagePair: (source: String, target: String)?

    func isReady(
        source: String = "da",
        target: String = "en"
    ) async -> Bool {
        do {
            _ = try request(
                texts: [],
                source: source,
                target: target
            )
            return true
        } catch {
            resetServer()
            return false
        }
    }

    func warmUp(
        source: String = "da",
        target: String = "en"
    ) async {
        _ = try? request(texts: [], source: source, target: target)
    }

    func isWordBridgeReady() async -> Bool {
        do {
            _ = try requestDefinitions(words: [])
            return true
        } catch {
            resetServer()
            return false
        }
    }

    func explainEnglishWordsInDanish(
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

    func translate(
        _ texts: [String],
        source: String = "da",
        target: String = "en"
    ) async throws -> [String] {
        guard !texts.isEmpty else {
            return []
        }

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
        try ensureServer(source: "en", target: "da")
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
        if let process,
           process.isRunning,
           activeLanguagePair?.source == source,
           activeLanguagePair?.target == target {
            return
        }
        resetServer()

        guard let pythonURL = Self.pythonURL,
              let bridgeURL = Self.bridgeURL else {
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

        do {
            try process.run()
        } catch {
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
        while true {
            if let newline = responseBuffer.firstIndex(of: 0x0A) {
                let line = responseBuffer[..<newline]
                responseBuffer.removeSubrange(...newline)
                return Data(line)
            }

            let chunk = output.availableData
            guard !chunk.isEmpty else {
                let message = errors
                    .map { String(decoding: $0.availableData, as: UTF8.self) }
                    .map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    } ?? ""
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

    private static var bridgeURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("LocalEngines/argos_bridge.py"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/LocalEngines/argos_bridge.py")
        ].compactMap { $0 }
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private static var pythonURL: URL? {
        let managedPython = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Babelstaarnet/argos-venv/bin/python3"
            )
        let fixedCandidates = [
            managedPython.path,
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        let pathCandidates = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map { String($0) + "/python3" } ?? []

        return (fixedCandidates + pathCandidates)
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

private struct BatchRequest: Encodable {
    let texts: [String]
}

private struct BatchResponse: Decodable {
    let translations: [String]
}

private struct WordBridgeRequest: Encodable {
    let defineWords: [String]

    enum CodingKeys: String, CodingKey {
        case defineWords = "define_words"
    }
}
