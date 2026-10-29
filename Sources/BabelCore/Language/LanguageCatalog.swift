import Foundation

public struct ReadingLanguage: Codable, Identifiable, Sendable, Hashable {
    public let id, name, nativeName, engineCode, locale, ocrWindows, tesseract, voice, sample: String
    public let ocrVision: [String]
    public let cjk: Bool
    public var displayName: String { name == nativeName ? name : name + " · " + nativeName }
}
public enum LanguageCatalog {
    private struct Catalog: Decodable { let languages: [ReadingLanguage] }
    public static let languages: [ReadingLanguage] = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("LanguagePacks/catalog.json")
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks/catalog.json")
        guard let data = [bundled, repository].compactMap({ $0 }).compactMap({ try? Data(contentsOf: $0) }).first,
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { preconditionFailure("Bundled language catalog is missing") }
        return catalog.languages
    }()
    public static func language(_ id: String) -> ReadingLanguage { languages.first { $0.id == id }! }
    public static func valid(_ id: String) -> Bool { languages.contains { $0.id == id } }
    public static func pairID(source: String, target: String) -> String { source + "--" + target }
    public static func modelEdges(source: String, target: String) -> [String] {
        let a = language(source).engineCode, b = language(target).engineCode
        if a == b { return [] }
        return a == "en" || b == "en" ? [a + "-" + b] : [a + "-en", "en-" + b]
    }
}
