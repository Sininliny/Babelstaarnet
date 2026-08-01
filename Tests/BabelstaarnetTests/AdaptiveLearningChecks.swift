import Foundation

@main
enum AdaptiveLearningChecks {
    static func main() {
        let suiteName = "AdaptiveLearningChecks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated defaults")
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let key = "test.words"
        let store = LearnerProfileStore(
            defaults: defaults,
            storageKey: key
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        precondition(
            LearnerProfileStore.normalizedKey(for: "  TØVER! ") == "tøver"
        )
        store.recordEncounter(for: "Tøver", at: now)
        let exposed = store.progress(for: "tøver", at: now)
        precondition(exposed.encounterCount == 1)
        precondition(exposed.familiarity == 0.12)
        precondition(exposed.level(at: now) == .new)

        store.recordKnown(for: "tøver", at: now)
        let familiar = store.progress(for: "TØVER", at: now)
        precondition(familiar.knownConfirmationCount == 1)
        precondition(familiar.level(at: now) == .familiar)
        precondition(store.familiarWordCount(at: now) == 1)

        let persistedStore = LearnerProfileStore(
            defaults: defaults,
            storageKey: key
        )
        precondition(
            persistedStore.progress(for: "tøver", at: now) == familiar
        )

        let exported = try! persistedStore.exportData(at: now)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try! decoder.decode(
            LearnerProfileArchive.self,
            from: exported
        )
        precondition(archive.schemaVersion == 1)
        precondition(archive.sourceLanguage == "da")
        precondition(archive.words.count == 1)

        persistedStore.reset()
        let firstImport = try! persistedStore.importArchiveData(
            exported,
            at: now
        )
        precondition(firstImport.importedWordCount == 1)
        precondition(firstImport.totalWordCount == 1)
        precondition(
            persistedStore.progress(for: "tøver", at: now) == familiar
        )
        let repeatedImport = try! persistedStore.importArchiveData(
            exported,
            at: now
        )
        precondition(repeatedImport.totalWordCount == 1)
        precondition(
            persistedStore.progress(for: "tøver", at: now) == familiar
        )

        let invalidArchive = LearnerProfileArchive(
            schemaVersion: 99,
            exportedAt: now,
            words: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let invalidData = try! encoder.encode(invalidArchive)
        do {
            try persistedStore.importArchiveData(invalidData, at: now)
            preconditionFailure("Unsupported archives must be rejected")
        } catch let error as LearnerProfileArchiveError {
            precondition(error == .unsupportedVersion(99))
        } catch {
            preconditionFailure("Unexpected archive error: \(error)")
        }

        let service = AdaptiveExplanationService()
        let danishOnly = service.explanation(
            bridgeText: "Hun er ikke sikker endnu.",
            englishMeaning: "hesitates",
            expandedEnglish: "To pause before doing something because you are unsure.",
            expandEnglish: false
        )
        precondition(danishOnly.englishSupport == nil)
        precondition(danishOnly.primaryText.hasPrefix("Hun"))

        store.recordUnknown(for: "tøver", at: now)
        let needsHelp = store.progress(for: "tøver", at: now)
        precondition(needsHelp.level(at: now) == .learning)
        let expanded = service.explanation(
            bridgeText: "Hun er ikke sikker endnu.",
            englishMeaning: "hesitates",
            expandedEnglish: "To pause before doing something because you are unsure.",
            expandEnglish: true
        )
        precondition(
            expanded.englishSupport
                == "To pause before doing something because you are unsure."
        )
        precondition(expanded.englishIsExpanded)

        let bilingual = service.explanation(
            bridgeText: "Useful materialer fra nature, som mennesker kan use.",
            englishMeaning: "natural resources",
            expandedEnglish: "“natural resources” — useful materials or supplies that come from nature, such as water, land, forests, minerals, and energy.",
            expandEnglish: false
        )
        precondition(bilingual.primaryText.split(separator: " ").count <= 20)
        precondition(bilingual.primaryText.hasSuffix("."))
        precondition(bilingual.primaryText.contains("nature"))
        precondition(bilingual.primaryText.contains("use"))
        precondition(bilingual.englishSupport == nil)
        precondition(!bilingual.primaryText.contains("…"))

        persistedStore.reset()
        precondition(persistedStore.trackedWordCount == 0)
        print("Adaptive local learning checks passed")
    }
}
