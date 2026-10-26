import Foundation

struct EngineInstallationProgress: Equatable, Sendable {
    var completedSteps = 0
    var totalSteps = 0
    var message = "Preparing installer"
    var detail: String?

    var fractionCompleted: Double? {
        totalSteps > 0 ? Double(completedSteps) / Double(totalSteps) : nil
    }

    init(message: String = "Preparing installer", completedSteps: Int = 0, totalSteps: Int = 0) {
        self.message = message
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
    }

    init?(line: String) {
        let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "BABELSTAARNET_PROGRESS",
              let completed = Int(parts[1]), let total = Int(parts[2]),
              total > 0, completed >= 0, completed <= total,
              !parts[3].isEmpty else { return nil }
        completedSteps = completed
        totalSteps = total
        message = String(parts[3])
    }
}

enum EngineInstallerError: LocalizedError {
    case installerMissing
    case installationInProgress
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .installerMissing:
            return "The local-engine installer is missing from this build."
        case .installationInProgress:
            return "Another engine installation is already running."
        case let .installationFailed(message):
            return message.isEmpty ? "Local-engine installation failed." : message
        }
    }
}

actor EngineInstallerService {
    typealias ProgressHandler = @MainActor @Sendable (EngineInstallationProgress) async -> Void
    private let scriptDirectory: URL?
    private var isRunning = false

    init() { scriptDirectory = nil }

    /// Fixture installers exercise the real process and pipe handling offline.
    init(scriptDirectory: URL) { self.scriptDirectory = scriptDirectory }

    func install(onProgress: @escaping ProgressHandler = { _ in }) async throws -> String {
        try await run(script: "install-local-engines.sh", onProgress: onProgress)
    }

    func installContextualGlosses(onProgress: @escaping ProgressHandler = { _ in }) async throws -> String {
        try await run(script: "install-contextual-glosses.sh", onProgress: onProgress)
    }

    private func run(script: String, onProgress: @escaping ProgressHandler) async throws -> String {
        guard !isRunning else { throw EngineInstallerError.installationInProgress }
        guard let installerURL = installerURL(named: script) else {
            throw EngineInstallerError.installerMissing
        }
        isRunning = true
        defer { isRunning = false }

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [installerURL.path]
            process.currentDirectoryURL = installerURL.deletingLastPathComponent()
            // GUI launches have no terminal to answer an installer's prompts.
            process.standardInput = FileHandle.nullDevice
            var environment = ProcessInfo.processInfo.environment
            let currentPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
            environment["HOMEBREW_NO_ANALYTICS"] = "1"
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            environment["PYTHONUNBUFFERED"] = "1"
            environment["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
            process.environment = environment

            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            defer { try? output.fileHandleForReading.close() }

            var progress = EngineInstallationProgress(message:
                script == "install-contextual-glosses.sh" ? "Installing language model" : "Preparing local engines"
            )
            var pending = Data()
            var tail = Data()
            let limit = 16_384
            await onProgress(progress)
            // Waiting for EOF hid every stage and error until setup ended.
            while true {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                tail.append(chunk)
                if tail.count > limit { tail.removeFirst(tail.count - limit) }
                pending.append(chunk)
                while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                    let line = String(decoding: pending[..<end], as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    pending.removeSubrange(...end)
                    if line.isEmpty { continue }
                    if let stage = EngineInstallationProgress(line: line) {
                        progress = stage
                    } else {
                        progress.detail = String(line.suffix(500))
                    }
                    await onProgress(progress)
                }
                if pending.count > limit { pending.removeFirst(pending.count - limit) }
            }
            if !pending.isEmpty {
                let line = String(decoding: pending, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let stage = EngineInstallationProgress(line: line) {
                    progress = stage
                } else {
                    progress.detail = String(line.suffix(500))
                }
                await onProgress(progress)
            }
            process.waitUntilExit()
            let message = String(decoding: tail, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else {
                throw EngineInstallerError.installationFailed(message)
            }
            return message
        }.value
    }

    /// Shipped builds execute only their bundled installer. The checkout
    /// fallback remains restricted to debug builds.
    private func installerURL(named script: String) -> URL? {
        if let scriptDirectory {
            let url = scriptDirectory.appendingPathComponent(script)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        var candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("LocalEngines/\(script)")
        ].compactMap { $0 }
#if DEBUG
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Scripts/\(script)")
        )
#endif
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
