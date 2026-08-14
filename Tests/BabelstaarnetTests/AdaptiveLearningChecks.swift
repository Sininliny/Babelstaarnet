import Foundation
@testable import BabelCore
@testable import BabelOCR
@testable import BabelTranslate
@testable import BabelLexicon
@testable import BabelSpeech
@testable import LanguageDanish
@testable import BabelstaarnetKit

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
            language: .danish,
            defaults: defaults,
            storageKey: key
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        precondition(
            LearnerProfileStore.normalizedKey(
                for: "  TØVER! ",
                locale: SourceLanguage.danish.locale
            ) == "tøver"
        )
        precondition(
            store.recordEncounter(
                for: "Tøver",
                context: "Hun tøver ved døren.",
                at: now
            )
        )
        let exposed = store.progress(for: "tøver", at: now)
        precondition(exposed.encounterCount == 1)
        precondition(exposed.spacedEncounterCount == 1)
        precondition(exposed.knowledgeLevel == 0)
        precondition(exposed.familiarity == 0)
        precondition(exposed.level(at: now) == .new)
        store.flushPersistence()
        let firstPersistedSnapshot = defaults.data(forKey: key)
        precondition(
            !store.recordEncounter(
                for: "Tøver",
                context: "Hun tøver ved døren.",
                at: now
            )
        )
        precondition(defaults.data(forKey: key) == firstPersistedSnapshot)

        store.recordKnown(for: "tøver", at: now)
        let firstStep = store.progress(for: "TØVER", at: now)
        precondition(firstStep.knowledgeLevel == 4)
        precondition(firstStep.knownConfirmationCount == 1)
        precondition(firstStep.level(at: now) == .familiar)
        precondition(store.familiarWordCount(at: now) == 1)

        // Repeated feedback in the same encounter cannot manufacture mastery.
        store.recordKnown(for: "tøver", at: now)
        precondition(store.progress(for: "tøver", at: now).knowledgeLevel == 4)

        let laterConfirmation = now.addingTimeInterval(24 * 60 * 60)
        store.recordKnown(for: "tøver", at: laterConfirmation)
        let capped = store.progress(for: "TØVER", at: laterConfirmation)
        precondition(
            capped.knowledgeLevel
                == LearnerWordProgress.maximumKnowledgeLevel
        )
        precondition(capped.level(at: laterConfirmation) == .established)
        precondition(store.isFamiliar("tøver", at: laterConfirmation))
        store.flushPersistence()

        let persistedStore = LearnerProfileStore(
            language: .danish,
            defaults: defaults,
            storageKey: key
        )
        precondition(
            persistedStore.progress(for: "tøver", at: laterConfirmation)
                == capped
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
        precondition(legacyProgress.spacedEncounterCount == 0)
        precondition(legacyProgress.lastSpacedEncounterAt == nil)
        precondition(legacyProgress.lastContextSignature == nil)

        precondition(
            persistedStore.contextSignature(
                for: "  Hun   tænker på svaret. "
            ) == persistedStore.contextSignature(
                for: "hun tænker på svaret."
            )
        )

        // Structural words start Danish-first, but explicit feedback wins.
        precondition(
            store.progress(for: "og", at: now).knowledgeLevel
                == AdaptiveKnowledgePolicy.knownLevel
        )
        store.recordUnknown(for: "og", at: now)
        precondition(store.progress(for: "og", at: now).knowledgeLevel == 0)

        let passiveStore = LearnerProfileStore(
            language: .danish,
            defaults: defaults,
            storageKey: "passive.words"
        )
        precondition(
            passiveStore.recordEncounter(
                for: "tænker",
                context: "Hun tænker på svaret.",
                at: now
            )
        )
        let nextDay = now.addingTimeInterval(24 * 60 * 60)
        precondition(
            !passiveStore.recordEncounter(
                for: "tænker",
                context: "Hun tænker på svaret.",
                at: nextDay
            )
        )
        precondition(
            passiveStore.progress(for: "tænker", at: nextDay)
                .spacedEncounterCount == 1
        )
        let contexts = [
            "Jeg tænker bedst om morgenen.",
            "De tænker over problemet.",
            "Vi tænker forskelligt.",
            "Han tænker på sin familie.",
            "Børn tænker kreativt.",
            "Man tænker klarere efter en pause."
        ]
        for (offset, context) in contexts.enumerated() {
            let date = now.addingTimeInterval(
                Double(offset + 2) * 24 * 60 * 60
            )
            passiveStore.recordEncounter(
                for: "tænker",
                context: context,
                at: date
            )
        }
        let passivelyLearned = passiveStore.progress(
            for: "tænker",
            at: now.addingTimeInterval(8 * 24 * 60 * 60)
        )
        precondition(passivelyLearned.spacedEncounterCount == 7)
        precondition(
            passivelyLearned.knowledgeLevel
                == AdaptiveKnowledgePolicy.passiveLearningLimit
        )
        precondition(!passiveStore.isFamiliar("tænker"))

        let retentionKey = "retention.words"
        let retentionStore = LearnerProfileStore(
            language: .danish,
            defaults: defaults,
            storageKey: retentionKey
        )
        retentionStore.recordKnown(for: "husker", at: now)
        let masteryDate = now.addingTimeInterval(24 * 60 * 60)
        retentionStore.recordKnown(for: "husker", at: masteryDate)
        let oneYearLater = masteryDate.addingTimeInterval(
            365 * 24 * 60 * 60
        )
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
        precondition(exposureOnly.lastReviewedAt == masteryDate)
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
                sourceLanguage: "da",
                exportedAt: exportedAt,
                words: [progress]
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try! encoder.encode(archive)
        }

        let mergeStore = LearnerProfileStore(
            language: .danish,
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
            sourceLanguage: "da",
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

        let service = AdaptiveExplanationService(language: .danish)
        for level in 0...3 {
            precondition(
                PassiveWordMeaningPolicy(language: .danish, target: .english)
            .directMeaning(
                    sourceWord: "studieboliger",
                    translation: "student accommodation",
                    knowledgeLevel: level
                ) == "student accommodation"
            )
        }
        for level in 4...5 {
            precondition(
                PassiveWordMeaningPolicy(language: .danish, target: .english)
            .directMeaning(
                    sourceWord: "studieboliger",
                    translation: "student accommodation",
                    knowledgeLevel: level
                ) == nil
            )
        }
        precondition(
            PassiveWordMeaningPolicy(language: .danish, target: .english)
            .directMeaning(
                sourceWord: "IKEA",
                translation: "IKEA",
                knowledgeLevel: 0
            ) == nil
        )
        precondition(
            PassiveWordMeaningPolicy(language: .danish, target: .english)
            .directMeaning(
                sourceWord: "udtryk",
                translation:
                    "an expression that is used in a particular situation",
                knowledgeLevel: 0
            ) == "an expression that is used in a particular situation"
        )
        precondition(
            PassiveWordMeaningPolicy(language: .danish, target: .english)
            .directMeaning(
                sourceWord: "udtryk",
                translation:
                    "a word or phrase that conveys an idea or emotion and is used in speech or writing",
                knowledgeLevel: 0
            ) == "a word or phrase that conveys an idea or emotion"
        )

        let danishOnly = service.explanation(
            bridgeText: "Hun er ikke sikker endnu.",
            englishMeaning: "hesitates",
            expandedEnglish: "To pause before doing something because you are unsure.",
            expandEnglish: false
        )
        precondition(danishOnly.englishSupport == nil)
        precondition(danishOnly.primaryText.hasPrefix("Hun"))

        store.recordUnknown(for: "tøver", at: laterConfirmation)
        let needsHelp = store.progress(for: "tøver", at: laterConfirmation)
        precondition(needsHelp.knowledgeLevel == 0)
        precondition(needsHelp.spacedEncounterCount == 0)
        precondition(needsHelp.level(at: laterConfirmation) == .new)
        precondition(!store.isFamiliar("tøver", at: laterConfirmation))
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

        store.recordUnknown(for: "tøver", at: laterConfirmation)
        precondition(
            store.progress(for: "tøver", at: laterConfirmation)
                .knowledgeLevel == 0
        )

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
