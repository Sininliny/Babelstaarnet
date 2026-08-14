import Foundation
import BabelCore
import BabelLexicon
import BabelOCR
import BabelSpeech
import BabelTranslate
import LanguageDanish

struct LearnerProfileArchive: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let sourceLanguage: String
    let exportedAt: Date
    let words: [LearnerWordProgress]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        sourceLanguage: String,
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
            return "This profile is for “\(language)”, which is not the language being read."
        case let .tooManyWords(count):
            return "This profile contains too many word records (\(count))."
        case let .invalidWord(word):
            return "The profile contains an invalid word record: “\(word)”."
        case let .invalidProgress(word):
            return "The profile contains invalid learning progress for “\(word)”."
        }
    }
}

enum AdaptiveKnowledgePolicy {
    static let knownLevel = 4
    static let masteredLevel = 5
    static let passiveLearningLimit = 3
    static let spacedEncounterInterval: TimeInterval = 20 * 60 * 60
    static let repeatedContextInterval: TimeInterval = 7 * 24 * 60 * 60

    static func levelAfterKnownFeedback(
        currentLevel: Int,
        lastReviewedAt: Date?,
        at date: Date
    ) -> Int {
        let current = min(
            max(currentLevel, 0),
            LearnerWordProgress.maximumKnowledgeLevel
        )
        guard current >= knownLevel else {
            return knownLevel
        }
        guard current < masteredLevel else {
            return masteredLevel
        }
        guard let lastReviewedAt else {
            return masteredLevel
        }
        return date.timeIntervalSince(lastReviewedAt)
            >= spacedEncounterInterval
            ? masteredLevel
            : knownLevel
    }

    static func levelAfterUnknownFeedback() -> Int {
        0
    }

    static func passiveLevel(forSpacedEncounterCount count: Int) -> Int {
        switch max(0, count) {
        case 0...1: 0
        case 2...3: 1
        case 4...6: 2
        default: passiveLearningLimit
        }
    }

    static func shouldCreditEncounter(
        lastCreditedAt: Date?,
        lastContextSignature: String?,
        contextSignature: String?,
        at date: Date
    ) -> Bool {
        guard let lastCreditedAt else {
            return true
        }
        let elapsed = date.timeIntervalSince(lastCreditedAt)
        guard elapsed >= spacedEncounterInterval else {
            return false
        }
        guard let lastContextSignature,
              let contextSignature,
              lastContextSignature == contextSignature else {
            return true
        }
        return elapsed >= repeatedContextInterval
    }
}

enum VocabularyPrior {
    /// The words the pack says a reader already knows start out known, so the
    /// frame of the sentence survives the first scan.
    static func initialKnowledgeLevel(
        for normalizedWord: String,
        in language: SourceLanguage
    ) -> Int {
        language.structuralWords.contains(normalizedWord)
            ? AdaptiveKnowledgePolicy.knownLevel
            : 0
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
    static let maximumKnowledgeLevel = 5

    let word: String
    var knowledgeLevel: Int
    var encounterCount: Int
    var moreEnglishCount: Int
    var knownConfirmationCount: Int
    var spacedEncounterCount: Int
    var lastSeen: Date
    var lastReviewedAt: Date?
    var lastSpacedEncounterAt: Date?
    var lastContextSignature: String?

    init(
        word: String,
        knowledgeLevel: Int,
        encounterCount: Int,
        moreEnglishCount: Int,
        knownConfirmationCount: Int,
        spacedEncounterCount: Int = 0,
        lastSeen: Date,
        lastReviewedAt: Date? = nil,
        lastSpacedEncounterAt: Date? = nil,
        lastContextSignature: String? = nil
    ) {
        self.word = word
        self.knowledgeLevel = knowledgeLevel
        self.encounterCount = encounterCount
        self.moreEnglishCount = moreEnglishCount
        self.knownConfirmationCount = knownConfirmationCount
        self.spacedEncounterCount = spacedEncounterCount
        self.lastSeen = lastSeen
        self.lastReviewedAt = lastReviewedAt
        self.lastSpacedEncounterAt = lastSpacedEncounterAt
        self.lastContextSignature = lastContextSignature
    }

    /// Kept as a normalized compatibility view for older profile archives.
    var familiarity: Double {
        Double(knowledgeLevel) / Double(Self.maximumKnowledgeLevel)
    }

    func effectiveKnowledgeLevel(at date: Date = Date()) -> Int {
        var effectiveLevel = min(
            max(knowledgeLevel, 0),
            Self.maximumKnowledgeLevel
        )
        guard effectiveLevel > 0,
              let lastReviewedAt else {
            return effectiveLevel
        }

        var elapsed = max(0, date.timeIntervalSince(lastReviewedAt))
        while effectiveLevel > 0 {
            let retention = Self.retentionInterval(
                for: effectiveLevel
            )
            guard elapsed >= retention else {
                break
            }
            elapsed -= retention
            effectiveLevel -= 1
        }
        return effectiveLevel
    }

    func effectiveFamiliarity(at date: Date = Date()) -> Double {
        Double(effectiveKnowledgeLevel(at: date))
            / Double(Self.maximumKnowledgeLevel)
    }

    func level(at date: Date = Date()) -> LearnerFamiliarity {
        switch effectiveKnowledgeLevel(at: date) {
        case 0: .new
        case 1...2: .learning
        case 3...4: .familiar
        default: .established
        }
    }

    private static func retentionInterval(for level: Int) -> TimeInterval {
        let day: TimeInterval = 24 * 60 * 60
        switch level {
        case 1: return 7 * day
        case 2: return 21 * day
        case 3: return 60 * day
        case 4: return 180 * day
        default: return 365 * day
        }
    }

    private enum CodingKeys: String, CodingKey {
        case word
        case knowledgeLevel
        case familiarity
        case encounterCount
        case moreEnglishCount
        case knownConfirmationCount
        case spacedEncounterCount
        case lastSeen
        case lastReviewedAt
        case lastSpacedEncounterAt
        case lastContextSignature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.decode(String.self, forKey: .word)
        if let storedLevel = try container.decodeIfPresent(
            Int.self,
            forKey: .knowledgeLevel
        ) {
            knowledgeLevel = storedLevel
        } else {
            let legacyFamiliarity = try container.decodeIfPresent(
                Double.self,
                forKey: .familiarity
            ) ?? 0
            knowledgeLevel = legacyFamiliarity.isFinite
                ? Int(
                    (legacyFamiliarity
                        * Double(Self.maximumKnowledgeLevel)).rounded()
                )
                : -1
        }
        encounterCount = try container.decode(
            Int.self,
            forKey: .encounterCount
        )
        moreEnglishCount = try container.decode(
            Int.self,
            forKey: .moreEnglishCount
        )
        knownConfirmationCount = try container.decode(
            Int.self,
            forKey: .knownConfirmationCount
        )
        spacedEncounterCount = try container.decodeIfPresent(
            Int.self,
            forKey: .spacedEncounterCount
        ) ?? 0
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        lastReviewedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .lastReviewedAt
        )
        if lastReviewedAt == nil,
           (knownConfirmationCount > 0 || moreEnglishCount > 0) {
            lastReviewedAt = lastSeen
        }
        lastSpacedEncounterAt = try container.decodeIfPresent(
            Date.self,
            forKey: .lastSpacedEncounterAt
        )
        lastContextSignature = try container.decodeIfPresent(
            String.self,
            forKey: .lastContextSignature
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(word, forKey: .word)
        try container.encode(knowledgeLevel, forKey: .knowledgeLevel)
        try container.encode(familiarity, forKey: .familiarity)
        try container.encode(encounterCount, forKey: .encounterCount)
        try container.encode(moreEnglishCount, forKey: .moreEnglishCount)
        try container.encode(
            knownConfirmationCount,
            forKey: .knownConfirmationCount
        )
        try container.encode(
            spacedEncounterCount,
            forKey: .spacedEncounterCount
        )
        try container.encode(lastSeen, forKey: .lastSeen)
        try container.encodeIfPresent(
            lastReviewedAt,
            forKey: .lastReviewedAt
        )
        try container.encodeIfPresent(
            lastSpacedEncounterAt,
            forKey: .lastSpacedEncounterAt
        )
        try container.encodeIfPresent(
            lastContextSignature,
            forKey: .lastContextSignature
        )
    }
}

final class LearnerProfileStore {
    static let maximumStoredWordCount = 100_000
    private let language: SourceLanguage
    private static let keyTrimmingCharacters =
        CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
    private static let encounterSaveBatchSize = 20
    private static let encounterSaveInterval: TimeInterval = 10

    private let defaults: UserDefaults
    private let storageKey: String
    private let persistenceQueue = DispatchQueue(
        label: "dev.sinin.babelstaarnet.learner-profile",
        qos: .utility
    )
    private var entries: [String: LearnerWordProgress]
    private var pendingEncounterSaves = 0
    private var lastSavedAt = Date.distantPast

    init(
        language: SourceLanguage,
        defaults: UserDefaults = .standard,
        storageKey: String = "learnerProfile.words"
    ) {
        self.language = language
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(
               [String: LearnerWordProgress].self,
               from: data
           ) {
            entries = decoded.filter {
                Self.isValid($0.value, locale: language.locale)
            }
        } else {
            entries = [:]
        }
    }

    var trackedWordCount: Int {
        entries.count
    }

    func familiarWordCount(at date: Date = Date()) -> Int {
        entries.values.filter {
            $0.effectiveKnowledgeLevel(at: date) >= 4
        }.count
    }

    func isFamiliar(
        _ word: String,
        at date: Date = Date()
    ) -> Bool {
        progress(for: word, at: date).effectiveKnowledgeLevel(at: date) >= 4
    }

    func progress(
        for word: String,
        at date: Date = Date()
    ) -> LearnerWordProgress {
        let key = normalizedKey(for: word)
        return entries[key] ?? LearnerWordProgress(
            word: key,
            knowledgeLevel: VocabularyPrior.initialKnowledgeLevel(
                for: key,
                in: language
            ),
            encounterCount: 0,
            moreEnglishCount: 0,
            knownConfirmationCount: 0,
            lastSeen: date
        )
    }

    /// Encounters are weak learning evidence. Only spaced encounters can
    /// reduce support, and they never silently establish mastery.
    @discardableResult
    func recordEncounter(
        for word: String,
        context: String? = nil,
        at date: Date = Date()
    ) -> Bool {
        let key = normalizedKey(for: word)
        guard !key.isEmpty else {
            return false
        }
        let isNewWord = entries[key] == nil
        makeRoomIfNeeded(for: key)
        var entry = progress(for: key, at: date)
        let previousLevel = entry.knowledgeLevel
        entry.encounterCount += 1
        entry.lastSeen = date
        let contextSignature = contextSignature(for: context)
        if AdaptiveKnowledgePolicy.shouldCreditEncounter(
            lastCreditedAt: entry.lastSpacedEncounterAt,
            lastContextSignature: entry.lastContextSignature,
            contextSignature: contextSignature,
            at: date
        ) {
            entry.spacedEncounterCount += 1
            entry.lastSpacedEncounterAt = date
            entry.lastContextSignature = contextSignature
            let passiveLevel = AdaptiveKnowledgePolicy.passiveLevel(
                forSpacedEncounterCount: entry.spacedEncounterCount
            )
            if entry.knowledgeLevel < AdaptiveKnowledgePolicy.knownLevel {
                entry.knowledgeLevel = max(
                    entry.effectiveKnowledgeLevel(at: date),
                    passiveLevel
                )
            }
        }
        entries[key] = entry
        pendingEncounterSaves += 1
        saveEncountersIfNeeded(at: date)
        return isNewWord || entry.knowledgeLevel != previousLevel
    }

    func recordUnknown(
        for word: String,
        at date: Date = Date()
    ) {
        let key = normalizedKey(for: word)
        guard !key.isEmpty else {
            return
        }
        makeRoomIfNeeded(for: key)
        var entry = progress(for: key, at: date)
        entry.knowledgeLevel =
            AdaptiveKnowledgePolicy.levelAfterUnknownFeedback()
        entry.moreEnglishCount += 1
        entry.spacedEncounterCount = 0
        entry.lastSeen = date
        entry.lastReviewedAt = date
        entry.lastSpacedEncounterAt = nil
        entry.lastContextSignature = nil
        entries[key] = entry
        save()
    }

    func recordKnown(
        for word: String,
        at date: Date = Date()
    ) {
        let key = normalizedKey(for: word)
        guard !key.isEmpty else {
            return
        }
        makeRoomIfNeeded(for: key)
        var entry = progress(for: key, at: date)
        entry.knowledgeLevel = AdaptiveKnowledgePolicy.levelAfterKnownFeedback(
            currentLevel: entry.effectiveKnowledgeLevel(at: date),
            lastReviewedAt: entry.lastReviewedAt,
            at: date
        )
        entry.knownConfirmationCount += 1
        entry.lastSeen = date
        entry.lastReviewedAt = date
        entries[key] = entry
        save()
    }

    func reset() {
        flushPersistence()
        entries.removeAll()
        pendingEncounterSaves = 0
        lastSavedAt = Date.distantPast
        defaults.removeObject(forKey: storageKey)
    }

    func exportData(at date: Date = Date()) throws -> Data {
        let archive = LearnerProfileArchive(
            sourceLanguage: language.code,
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
            let key = normalizedKey(for: imported.word)
            let existing = entries[key]
            let preferredProgress = Self.progressWithNewestReview(
                existing,
                imported,
                at: date
            )
            let newestSpacedProgress = Self.progressWithNewestEncounter(
                existing,
                imported
            )
            entries[key] = LearnerWordProgress(
                word: key,
                knowledgeLevel: preferredProgress.knowledgeLevel,
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
                spacedEncounterCount: max(
                    existing?.spacedEncounterCount ?? 0,
                    imported.spacedEncounterCount
                ),
                lastSeen: max(
                    existing?.lastSeen ?? imported.lastSeen,
                    imported.lastSeen
                ),
                lastReviewedAt: preferredProgress.lastReviewedAt,
                lastSpacedEncounterAt:
                    newestSpacedProgress.lastSpacedEncounterAt,
                lastContextSignature:
                    newestSpacedProgress.lastContextSignature
            )
        }
        pruneToStorageLimit()
        save()
        return LearnerProfileImportSummary(
            importedWordCount: archive.words.count,
            totalWordCount: entries.count
        )
    }

    /// The stored form of a word. Takes a locale explicitly so it can be
    /// used while a store is still being initialised, before its language is
    /// reachable through `self`.
    static func normalizedKey(for word: String, locale: Locale) -> String {
        word.precomposedStringWithCanonicalMapping
            .lowercased(with: locale)
            .trimmingCharacters(
                in: Self.keyTrimmingCharacters
            )
    }

    func normalizedKey(for word: String) -> String {
        Self.normalizedKey(for: word, locale: language.locale)
    }

    func contextSignature(for context: String?) -> String? {
        guard let context else {
            return nil
        }
        let compact = context
            .precomposedStringWithCanonicalMapping
            .lowercased(with: language.locale)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else {
            return nil
        }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in compact.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    func flushPersistence() {
        persistenceQueue.sync {}
    }

    private func save() {
        let snapshot = entries
        let defaults = self.defaults
        let storageKey = self.storageKey
        persistenceQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else {
                return
            }
            defaults.set(data, forKey: storageKey)
        }
        pendingEncounterSaves = 0
        lastSavedAt = Date()
    }

    private func saveEncountersIfNeeded(at date: Date) {
        guard pendingEncounterSaves >= Self.encounterSaveBatchSize
                || date.timeIntervalSince(lastSavedAt)
                    >= Self.encounterSaveInterval else {
            return
        }
        save()
    }

    private func makeRoomIfNeeded(for key: String) {
        guard entries[key] == nil,
              entries.count >= Self.maximumStoredWordCount else {
            return
        }
        pruneToStorageLimit(
            target: Self.maximumStoredWordCount - 1_000
        )
    }

    private func pruneToStorageLimit(
        target: Int = LearnerProfileStore.maximumStoredWordCount
    ) {
        guard entries.count > target else {
            return
        }
        let removalCount = entries.count - target
        let leastValuable = entries.values.sorted { left, right in
            let leftScore = (
                left.knowledgeLevel,
                left.knownConfirmationCount,
                left.moreEnglishCount,
                left.lastSeen
            )
            let rightScore = (
                right.knowledgeLevel,
                right.knownConfirmationCount,
                right.moreEnglishCount,
                right.lastSeen
            )
            if leftScore.0 != rightScore.0 {
                return leftScore.0 < rightScore.0
            }
            if leftScore.1 != rightScore.1 {
                return leftScore.1 < rightScore.1
            }
            if leftScore.2 != rightScore.2 {
                return leftScore.2 < rightScore.2
            }
            return leftScore.3 < rightScore.3
        }.prefix(removalCount)
        for progress in leastValuable {
            entries.removeValue(forKey: progress.word)
        }
    }

    private static func isValid(
        _ word: LearnerWordProgress,
        locale: Locale
    ) -> Bool {
        let key = normalizedKey(for: word.word, locale: locale)
        return !key.isEmpty
            && key.count <= 100
            && (0...LearnerWordProgress.maximumKnowledgeLevel).contains(
                word.knowledgeLevel
            )
            && word.encounterCount >= 0
            && word.moreEnglishCount >= 0
            && word.knownConfirmationCount >= 0
            && word.spacedEncounterCount >= 0
            && word.spacedEncounterCount <= word.encounterCount
            && (word.lastContextSignature?.count ?? 0) <= 64
    }

    private static func progressWithNewestReview(
        _ existing: LearnerWordProgress?,
        _ imported: LearnerWordProgress,
        at date: Date
    ) -> LearnerWordProgress {
        guard let existing else {
            return imported
        }
        switch (existing.lastReviewedAt, imported.lastReviewedAt) {
        case let (existingDate?, importedDate?) where existingDate != importedDate:
            return existingDate > importedDate ? existing : imported
        case (nil, _?):
            return imported
        case (_?, nil):
            return existing
        default:
            let existingLevel = existing.effectiveKnowledgeLevel(at: date)
            let importedLevel = imported.effectiveKnowledgeLevel(at: date)
            return existingLevel <= importedLevel ? existing : imported
        }
    }

    private static func progressWithNewestEncounter(
        _ existing: LearnerWordProgress?,
        _ imported: LearnerWordProgress
    ) -> LearnerWordProgress {
        guard let existing else {
            return imported
        }
        switch (
            existing.lastSpacedEncounterAt,
            imported.lastSpacedEncounterAt
        ) {
        case let (existingDate?, importedDate?):
            return existingDate >= importedDate ? existing : imported
        case (nil, _?):
            return imported
        default:
            return existing
        }
    }

    private func validate(_ archive: LearnerProfileArchive) throws {
        guard archive.schemaVersion == LearnerProfileArchive.currentSchemaVersion else {
            throw LearnerProfileArchiveError.unsupportedVersion(
                archive.schemaVersion
            )
        }
        guard archive.sourceLanguage == language.code else {
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
            let key = normalizedKey(for: word.word)
            guard !key.isEmpty,
                  key.count <= 100 else {
                throw LearnerProfileArchiveError.invalidWord(word.word)
            }
            guard Self.isValid(word, locale: language.locale) else {
                throw LearnerProfileArchiveError.invalidProgress(word.word)
            }
        }
    }
}
