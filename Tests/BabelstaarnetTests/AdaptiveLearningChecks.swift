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
        precondition(store.recordEncounter(for: "Tøver", at: now))
        let exposed = store.progress(for: "tøver", at: now)
        precondition(exposed.encounterCount == 1)
        precondition(exposed.knowledgeLevel == 0)
        precondition(exposed.familiarity == 0)
        precondition(exposed.level(at: now) == .new)
        store.flushPersistence()
        let firstPersistedSnapshot = defaults.data(forKey: key)
        precondition(!store.recordEncounter(for: "Tøver", at: now))
        precondition(defaults.data(forKey: key) == firstPersistedSnapshot)

        store.recordKnown(for: "tøver", at: now)
        let firstStep = store.progress(for: "TØVER", at: now)
        precondition(firstStep.knowledgeLevel == 1)
        precondition(firstStep.knownConfirmationCount == 1)
        precondition(firstStep.level(at: now) == .learning)
        precondition(firstStep.knowledgeStageTitle(at: now) == "Recognizing")
        precondition(store.familiarWordCount(at: now) == 0)

        store.recordKnown(for: "tøver", at: now)
        store.recordKnown(for: "tøver", at: now)
        store.recordKnown(for: "tøver", at: now)
        let familiar = store.progress(for: "TØVER", at: now)
        precondition(familiar.knowledgeLevel == 4)
        precondition(familiar.knownConfirmationCount == 4)
        precondition(familiar.level(at: now) == .familiar)
        precondition(familiar.knowledgeStageTitle(at: now) == "Known")
        precondition(store.familiarWordCount(at: now) == 1)
        precondition(store.isFamiliar("tøver", at: now))

        store.recordKnown(for: "tøver", at: now)
        store.recordKnown(for: "tøver", at: now)
        let capped = store.progress(for: "TØVER", at: now)
        precondition(
            capped.knowledgeLevel
                == LearnerWordProgress.maximumKnowledgeLevel
        )
        precondition(capped.level(at: now) == .established)
        precondition(capped.knowledgeStageTitle(at: now) == "Mastered")
        store.flushPersistence()

        let persistedStore = LearnerProfileStore(
            defaults: defaults,
            storageKey: key
        )
        precondition(
            persistedStore.progress(for: "tøver", at: now) == capped
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
        precondition(
            archive.words[0].knowledgeLevel
                == LearnerWordProgress.maximumKnowledgeLevel
        )

        let legacyJSON = """
        {
          "word": "gammel",
          "familiarity": 0.8,
          "encounterCount": 3,
          "moreEnglishCount": 0,
          "knownConfirmationCount": 2,
          "lastSeen": \(now.timeIntervalSinceReferenceDate)
        }
        """
        let legacyProgress = try! JSONDecoder().decode(
            LearnerWordProgress.self,
            from: Data(legacyJSON.utf8)
        )
        precondition(legacyProgress.knowledgeLevel == 4)
        precondition(legacyProgress.lastReviewedAt == now)

        let retentionKey = "retention.words"
        let retentionStore = LearnerProfileStore(
            defaults: defaults,
            storageKey: retentionKey
        )
        for _ in 0..<LearnerWordProgress.maximumKnowledgeLevel {
            retentionStore.recordKnown(for: "husker", at: now)
        }
        let oneYearLater = now.addingTimeInterval(365 * 24 * 60 * 60)
        precondition(
            retentionStore.progress(for: "husker", at: oneYearLater)
                .effectiveKnowledgeLevel(at: oneYearLater) == 4
        )
        retentionStore.recordEncounter(for: "husker", at: oneYearLater)
        let exposureOnly = retentionStore.progress(
            for: "husker",
            at: oneYearLater
        )
        precondition(exposureOnly.lastSeen == oneYearLater)
        precondition(exposureOnly.lastReviewedAt == now)
        precondition(
            exposureOnly.effectiveKnowledgeLevel(at: oneYearLater) == 4
        )
        retentionStore.recordKnown(for: "husker", at: oneYearLater)
        let refreshedMastery = retentionStore.progress(
            for: "husker",
            at: oneYearLater
        )
        precondition(refreshedMastery.knowledgeLevel == 5)
        precondition(refreshedMastery.lastReviewedAt == oneYearLater)

        persistedStore.reset()
        let firstImport = try! persistedStore.importArchiveData(
            exported,
            at: now
        )
        precondition(firstImport.importedWordCount == 1)
        precondition(firstImport.totalWordCount == 1)
        precondition(
            persistedStore.progress(for: "tøver", at: now) == capped
        )

        func archiveData(
            _ progress: LearnerWordProgress,
            exportedAt: Date
        ) -> Data {
            let archive = LearnerProfileArchive(
                exportedAt: exportedAt,
                words: [progress]
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try! encoder.encode(archive)
        }

        let mergeStore = LearnerProfileStore(
            defaults: defaults,
            storageKey: "merge.words"
        )
        let olderMastery = LearnerWordProgress(
            word: "husker",
            knowledgeLevel: 5,
            encounterCount: 8,
            moreEnglishCount: 0,
            knownConfirmationCount: 5,
            lastSeen: now,
            lastReviewedAt: now
        )
        let laterDate = now.addingTimeInterval(24 * 60 * 60)
        let newerUncertainty = LearnerWordProgress(
            word: "husker",
            knowledgeLevel: 2,
            encounterCount: 9,
            moreEnglishCount: 1,
            knownConfirmationCount: 5,
            lastSeen: laterDate,
            lastReviewedAt: laterDate
        )
        let olderData = archiveData(olderMastery, exportedAt: now)
        let newerData = archiveData(newerUncertainty, exportedAt: laterDate)
        try! mergeStore.importArchiveData(olderData, at: laterDate)
        try! mergeStore.importArchiveData(newerData, at: laterDate)
        precondition(
            mergeStore.progress(for: "husker", at: laterDate).knowledgeLevel
                == 2
        )
        try! mergeStore.importArchiveData(olderData, at: laterDate)
        precondition(
            mergeStore.progress(for: "husker", at: laterDate).knowledgeLevel
                == 2
        )
        let repeatedImport = try! persistedStore.importArchiveData(
            exported,
            at: now
        )
        precondition(repeatedImport.totalWordCount == 1)
        precondition(
            persistedStore.progress(for: "tøver", at: now) == capped
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
        store.recordUnknown(for: "tøver", at: now)
        store.recordUnknown(for: "tøver", at: now)
        let needsHelp = store.progress(for: "tøver", at: now)
        precondition(needsHelp.knowledgeLevel == 2)
        precondition(needsHelp.level(at: now) == .learning)
        precondition(!store.isFamiliar("tøver", at: now))
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

        store.recordUnknown(for: "tøver", at: now)
        store.recordUnknown(for: "tøver", at: now)
        store.recordUnknown(for: "tøver", at: now)
        precondition(store.progress(for: "tøver", at: now).knowledgeLevel == 0)

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
