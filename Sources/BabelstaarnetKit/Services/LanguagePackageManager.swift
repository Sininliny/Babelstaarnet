import Foundation
import Combine
import AppKit
import BabelCore

struct LanguagePackageState: Decodable {
    var runtime = false
    var conversion = false
    var models: [String] = []
    var installed: [String] = []
    func ready(source: String, target: String) -> Bool {
        let edges = LanguageCatalog.modelEdges(source: source, target: target)
        return edges.allSatisfy(models.contains) && (edges.isEmpty || runtime)
            && (!(LanguageCatalog.language(source).cjk || LanguageCatalog.language(target).cjk) || conversion)
    }
}

@MainActor final class LanguagePackageManager: ObservableObject {
    static var selection: (source: String, target: String) {
        let defaults = UserDefaults.standard
        let a = defaults.string(forKey: "languages.source") ?? "da"
        let b = defaults.string(forKey: "languages.target") ?? "en"
        return LanguageCatalog.valid(a) && LanguageCatalog.valid(b) && a != b ? (a, b) : ("da", "en")
    }
    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Babelstaarnet")
    }
    static func profileURL(source: String, target: String) -> URL {
        source == "da" && target == "en" ? root : root.appendingPathComponent("Profiles/" + LanguageCatalog.pairID(source: source, target: target))
    }
    let active = LanguagePackageManager.selection
    @Published var source = LanguagePackageManager.selection.source
    @Published var target = LanguagePackageManager.selection.target
    @Published private(set) var state = LanguagePackageState()
    @Published private(set) var busy = false
    @Published private(set) var message = "Installing uses the internet. Reading stays offline."
    var valid: Bool { source != target }
    var changed: Bool { source != active.source || target != active.target }
    var pairID: String { LanguageCatalog.pairID(source: source, target: target) }
    var route: String {
        let edges = LanguageCatalog.modelEdges(source: source, target: target)
        return edges.isEmpty ? "Local Chinese script conversion" : edges.count == 1 ? "Direct offline model" : "Offline translation via English"
    }
    private static var directory: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("LocalEngines"), FileManager.default.fileExists(atPath: bundled.appendingPathComponent("language_support.py").path) { return bundled }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LocalEngines")
    }
    func saveSelection() {
        guard valid, !busy else { return }
        UserDefaults.standard.set(source, forKey: "languages.source")
        UserDefaults.standard.set(target, forKey: "languages.target")
    }
    func manage(_ operation: String) async {
        guard !busy, valid else { return }
        if operation == "status", !FileManager.default.isExecutableFile(atPath: InstalledEngineLocations.managedPython) { state = LanguagePackageState(); message = "Translation runtime not installed. Choose Install translation to set it up."; return }
        busy = true; message = operation == "status" ? "Checking installed components…" : "Preparing components…"
        defer { busy = false }
        let source = source, target = target, active = active
        let folder = Self.directory, root = Self.root
        do {
            let output = try await Task.detached(priority: .utility) {
                let process = Process(), pipe = Pipe()
                if operation == "install" {
                    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    let bundled = folder.appendingPathComponent("install-language-support.sh")
                    let script = FileManager.default.fileExists(atPath: bundled.path) ? bundled : folder.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/install-language-support.sh")
                    process.arguments = [script.path, source, target]
                } else {
                    process.executableURL = URL(fileURLWithPath: InstalledEngineLocations.managedPython)
                    process.arguments = ["-I", "-X", "utf8", folder.appendingPathComponent("language_support.py").path, operation, "--data-directory", root.path, "--source", source, "--target", target, "--keep-source", active.source, "--keep-target", active.target]
                }
                process.standardOutput = pipe; process.standardError = pipe
                try process.run()
                var bytes = Data()
                while true {
                    let chunk = pipe.fileHandleForReading.availableData
                    if chunk.isEmpty { break }; bytes.append(chunk)
                    if bytes.count > 256_000 { bytes.removeFirst(bytes.count - 256_000) }
                }
                process.waitUntilExit()
                let text = String(decoding: bytes, as: UTF8.self)
                guard process.terminationStatus == 0 else { throw NSError(domain: "LanguageSetup", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(text.suffix(1600))]) }
                return text
            }.value
            struct Result: Decodable { let result: LanguagePackageState }
            guard let result = output.split(separator: "\n").reversed().compactMap({ try? JSONDecoder().decode(Result.self, from: Data($0.utf8)) }).first else { throw NSError(domain: "LanguageSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Setup returned no component status."]) }
            state = result.result
            message = operation == "remove" ? "Direction removed. Shared components and existing models were kept where needed. Learning records were kept." : state.ready(source: source, target: target) ? "Translation components ready. Reading stays offline." : "Some translation components are missing."
        } catch { message = error.localizedDescription }
    }
}
