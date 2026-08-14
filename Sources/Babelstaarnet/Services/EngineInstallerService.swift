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

    /// The bundled installer, plus the checkout's copy when this is a debug
    /// build.
    ///
    /// This one is passed to `/bin/zsh`, so a relative path resolved against
    /// the process's working directory is a script of someone else's choosing
    /// run as the user, reached by pressing **Install engines**. A launch from
    /// Finder has a working directory of `/` and would never find it, but that
    /// is the launcher's doing rather than this app's. Development builds keep
    /// the convenience because a developer already chose the directory they
    /// ran from; shipped builds read the installer only from inside the
    /// bundle.
    private static var installerURL: URL? {
        var candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent(
                    "LocalEngines/install-local-engines.sh"
                )
        ].compactMap { $0 }
#if DEBUG
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Scripts/install-local-engines.sh")
        )
#endif

        return candidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
}
