import Foundation

enum EngineInstallerError: LocalizedError {
    case installerMissing
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .installerMissing:
            return "The local-engine installer is missing from this build."
        case let .installationFailed(message):
            return message.isEmpty
                ? "Local-engine installation failed."
                : message
        }
    }
}

actor EngineInstallerService {
    func install() async throws -> String {
        guard let installerURL = Self.installerURL else {
            throw EngineInstallerError.installerMissing
        }

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [installerURL.path]

            var environment = ProcessInfo.processInfo.environment
            let currentPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
            environment["HOMEBREW_NO_ANALYTICS"] = "1"
            process.environment = environment

            let output = Pipe()
            process.standardOutput = output
            process.standardError = output

            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                throw EngineInstallerError.installationFailed(message)
            }
            return message
        }.value
    }

    private static var installerURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent(
                    "LocalEngines/install-local-engines.sh"
                ),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Scripts/install-local-engines.sh")
        ].compactMap { $0 }

        return candidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
}
