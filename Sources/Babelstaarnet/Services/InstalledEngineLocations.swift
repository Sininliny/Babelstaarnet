import Foundation

/// The absolute paths the optional local engines are accepted from.
///
/// Resolving an engine used to end with a walk of `$PATH`, which lets an
/// environment variable decide what this app executes. A GUI launch gets a
/// short system `PATH`, but a launch from a shell — `make run`, or opening the
/// bundle from a terminal — inherits whatever that shell has, and the first
/// writable directory on it is somewhere a binary named `tesseract` or
/// `python3` can be dropped for this app to find. The processes started here
/// are handed the capture and the text read out of it, so choosing the wrong
/// one hands over the screen.
///
/// Both engines only ever arrive from a package manager or from the app
/// bundle, and those write to paths that are known in advance. Writing the
/// list down costs an installation in an unusual place — which is not found
/// rather than guessed at, and leaves reading on Apple's Vision and
/// Translation — and in exchange nothing outside this file can extend what the
/// app is willing to run.
enum InstalledEngineLocations {
    /// Homebrew on Apple silicon, Homebrew on Intel, MacPorts, and the system.
    /// `/usr/local/bin` is group-writable by admins wherever Homebrew created
    /// it, so it is not a trust boundary on its own; it is here because
    /// removing it would break every Intel Homebrew installation, and an
    /// attacker who can write there can equally replace the real engine.
    private static let packageManagerDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
        "/usr/bin",
    ]

    static var tesseract: [String] {
        let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("LocalEngines/tesseract").path
        return [bundled].compactMap { $0 }
            + packageManagerDirectories.map { $0 + "/tesseract" }
    }

    static var python: [String] {
        let managed = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Babelstaarnet/argos-venv/bin/python3"
            ).path
        return [managed]
            + packageManagerDirectories.map { $0 + "/python3" }
    }
}
