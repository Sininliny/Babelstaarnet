import Foundation

struct LearnerProfileArchive: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let sourceLanguage: String
    let exportedAt: Date
    let words: [LearnerWordProgress]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        sourceLanguage: String = "da",
        exportedAt: Date,
        words: [LearnerWordProgress]
    ) {
        self.schemaVersion = schemaVersion
        self.sourceLanguage = sourceLanguage
        self.exportedAt = exportedAt
        self.words = words
    }
}

struct LearnerProfileImportSummary: Equatable, Sendable {
    let importedWordCount: Int
    let totalWordCount: Int
}

enum LearnerProfileArchiveError: LocalizedError, Equatable {
    case archiveTooLarge(Int)
    case unsupportedVersion(Int)
    case unexpectedLanguage(String)
    case tooManyWords(Int)
    case invalidWord(String)
    case invalidProgress(String)

    var errorDescription: String? {
        switch self {
        case let .archiveTooLarge(byteCount):
            return "This learning profile is too large to import (\(byteCount) bytes)."
        case let .unsupportedVersion(version):
            return "This learning profile uses unsupported format version \(version)."
        case let .unexpectedLanguage(language):
            return "This profile is for “\(language)”, not Danish."
        case let .tooManyWords(count):
            return "This profile contains too many word records (\(count))."
        case let .invalidWord(word):
            return "The profile contains an invalid word record: “\(word)”."
        case let .invalidProgress(word):
            return "The profile contains invalid learning progress for “\(word)”."
        }
    }
}

enum LearnerFamiliarity: String, Codable, Sendable {
    case new
    case learning
    case familiar
    case established

    var title: String {
        switch self {
        case .new:
            return "New word"
        case .learning:
            return "Learning"
        case .familiar:
            return "Probably understood"
        case .established:
            return "Well established"
        }
    }
}

struct LearnerWordProgress: Codable, Equatable, Sendable {
    let word: String
    var familiarity: Double
    var encounterCount: Int
    var moreEnglishCount: Int
    var knownConfirmationCount: Int
    var lastSeen: Date

    func effectiveFamiliarity(at date: Date = Date()) -> Double {
        let elapsed = max(0, date.timeIntervalSince(lastSeen))
        let halfLife = 180.0 * 24 * 60 * 60
        return familiarity * pow(0.5, elapsed / halfLife)
    }

    func level(at date: Date = Date()) -> LearnerFamiliarity {
        switch effectiveFamiliarity(at: date) {
        case ..<0.25:
            return .new
        case ..<0.65:
            return .learning
        case ..<0.88:
            return .familiar
        default:
            return .established
        }
    }
}

final class LearnerProfileStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private var entries: [String: LearnerWordProgress]

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "learnerProfile.words"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(
               [String: LearnerWordProgress].self,
               from: data
           ) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    var trackedWordCount: Int {
        entries.count
    }

    func familiarWordCount(at date: Date = Date()) -> Int {
        entries.values.filter {
            $0.effectiveFamiliarity(at: date) >= 0.65
        }.count
    }

    func isFamiliar(
        _ word: String,
        at date: Date = Date()
    ) -> Bool {
        progress(for: word, at: date).effectiveFamiliarity(at: date) >= 0.65
    }

    func progress(
        for word: String,
        at date: Date = Date()
    ) -> LearnerWordProgress {
        let key = Self.normalizedKey(for: word)
        return entries[key] ?? LearnerWordProgress(
            word: key,
            familiarity: 0.12,
            encounterCount: 0,
            moreEnglishCount: 0,
            knownConfirmationCount: 0,
            lastSeen: date
        )
    }

    /// A hover is an exposure only. It must not silently increase mastery.
    func recordEncounter(
        for word: String,
        at date: Date = Date()
    ) {
        let key = Self.normalizedKey(for: word)
        guard !key.isEmpty else {
            return
        }
        var entry = progress(for: key, at: date)
        entry.encounterCount += 1
        entry.lastSeen = date
        entries[key] = entry
        save()
    }

    func recordUnknown(
        for word: String,
        at date: Date = Date()
    ) {
        let key = Self.normalizedKey(for: word)
        guard !key.isEmpty else {
            return
        }
        var entry = progress(for: key, at: date)
        entry.familiarity = max(
            0,
            entry.effectiveFamiliarity(at: date) - 0.28
        )
        entry.moreEnglishCount += 1
        entry.lastSeen = date
        entries[key] = entry
        save()
    }

    func recordKnown(
        for word: String,
        at date: Date = Date()
    ) {
        let key = Self.normalizedKey(for: word)
        guard !key.isEmpty else {
            return
        }
        var entry = progress(for: key, at: date)
        entry.familiarity = min(
            1,
            entry.effectiveFamiliarity(at: date) + 0.58
        )
        entry.knownConfirmationCount += 1
        entry.lastSeen = date
        entries[key] = entry
        save()
    }

    func reset() {
        entries.removeAll()
        defaults.removeObject(forKey: storageKey)
    }

    func exportData(at date: Date = Date()) throws -> Data {
        let archive = LearnerProfileArchive(
            exportedAt: date,
            words: entries.values.sorted { $0.word < $1.word }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    @discardableResult
    func importArchiveData(
        _ data: Data,
        at date: Date = Date()
    ) throws -> LearnerProfileImportSummary {
        guard data.count <= 25_000_000 else {
            throw LearnerProfileArchiveError.archiveTooLarge(data.count)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(
            LearnerProfileArchive.self,
            from: data
        )
        try validate(archive)

        for imported in archive.words {
            let key = Self.normalizedKey(for: imported.word)
            let existing = entries[key]
            let strongerProgress: LearnerWordProgress
            if let existing,
               existing.effectiveFamiliarity(at: date)
                >= imported.effectiveFamiliarity(at: date) {
                strongerProgress = existing
            } else {
                strongerProgress = imported
            }
            entries[key] = LearnerWordProgress(
                word: key,
                familiarity: strongerProgress.familiarity,
                encounterCount: max(
                    existing?.encounterCount ?? 0,
                    imported.encounterCount
                ),
                moreEnglishCount: max(
                    existing?.moreEnglishCount ?? 0,
                    imported.moreEnglishCount
                ),
                knownConfirmationCount: max(
                    existing?.knownConfirmationCount ?? 0,
                    imported.knownConfirmationCount
                ),
                lastSeen: strongerProgress.lastSeen
            )
        }
        save()
        return LearnerProfileImportSummary(
            importedWordCount: archive.words.count,
            totalWordCount: entries.count
        )
    }

    static func normalizedKey(for word: String) -> String {
        word.precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "da_DK"))
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines
                    .union(.punctuationCharacters)
                    .union(.symbols)
            )
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private func validate(_ archive: LearnerProfileArchive) throws {
        guard archive.schemaVersion == LearnerProfileArchive.currentSchemaVersion else {
            throw LearnerProfileArchiveError.unsupportedVersion(
                archive.schemaVersion
            )
        }
        guard archive.sourceLanguage == "da" else {
            throw LearnerProfileArchiveError.unexpectedLanguage(
                archive.sourceLanguage
            )
        }
        guard archive.words.count <= 100_000 else {
            throw LearnerProfileArchiveError.tooManyWords(
                archive.words.count
            )
        }
        for word in archive.words {
            let key = Self.normalizedKey(for: word.word)
            guard !key.isEmpty,
                  key.count <= 100 else {
                throw LearnerProfileArchiveError.invalidWord(word.word)
            }
            guard word.familiarity.isFinite,
                  (0...1).contains(word.familiarity),
                  word.encounterCount >= 0,
                  word.moreEnglishCount >= 0,
                  word.knownConfirmationCount >= 0 else {
                throw LearnerProfileArchiveError.invalidProgress(word.word)
            }
        }
    }
}
