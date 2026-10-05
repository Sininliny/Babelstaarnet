import Foundation
@testable import BabelCore
@testable import BabelstaarnetKit
@testable import LanguageDanish

@main
enum WordReviewChecks {
    @MainActor
    static func main() {
        let suiteName = "WordReviewChecks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated defaults")
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let hour: TimeInterval = 60 * 60
        let day = 24 * hour

        // Each level waits longer, and comes back before the level fades.
        var previous: TimeInterval = 0
        for level in 0...5 {
            let interval = WordReviewPolicy.interval(forLevel: level)
            precondition(interval > previous)
            previous = interval
        }
        precondition(WordReviewPolicy.interval(forLevel: 1) < 7 * day)
        precondition(WordReviewPolicy.interval(forLevel: 2) < 21 * day)
        precondition(WordReviewPolicy.interval(forLevel: 3) < 60 * day)

        precondition(WordReviewPolicy.levelAfterReview(currentLevel: 0, remembered: true) == 1)
        precondition(WordReviewPolicy.levelAfterReview(currentLevel: 5, remembered: true) == 5)
        precondition(WordReviewPolicy.levelAfterReview(currentLevel: 3, remembered: false) == 0)

        let store = LearnerProfileStore(
            language: .danish,
            defaults: defaults,
            storageKey: "words"
        )

        // A word marked unknown while reading is due an hour later, and a
        // remembered review pushes it a day further.
        store.recordUnknown(for: "græsplæne", at: now)
        let marked = store.progress(for: "græsplæne", at: now)
        precondition(
            WordReviewPolicy.dueDate(for: marked, savedAt: now, at: now)
                == now.addingTimeInterval(hour)
        )
        let later = now.addingTimeInterval(2 * hour)
        store.recordReview(for: "græsplæne", remembered: true, at: later)
        let reviewed = store.progress(for: "græsplæne", at: later)
        precondition(reviewed.knowledgeLevel == 1)
        precondition(
            WordReviewPolicy.dueDate(for: reviewed, savedAt: now, at: later)
                == later.addingTimeInterval(day)
        )
        store.recordReview(for: "græsplæne", remembered: false, at: later)
        precondition(store.progress(for: "græsplæne", at: later).knowledgeLevel == 0)

        // A form not met yet borrows from its dictionary form, one level
        // lower and never past the level left untranslated.
        store.recordKnown(for: "gå", at: now)
        precondition(store.progress(for: "gik", at: now).knowledgeLevel == 0)
        store.recordLemma("gå", forForm: "Gik")
        precondition(store.lemma(forKey: "gik") == "gå")
        precondition(store.progress(for: "gik", at: now).knowledgeLevel == 3)
        // Free text from the model is not taken for a dictionary form.
        store.recordLemma("at gå hjem", forForm: "går")
        precondition(store.lemma(forKey: "går") == nil)
        store.recordLemma("gik", forForm: "gik")
        precondition(store.lemma(forKey: "gik") == "gå")

        store.flushPersistence()
        let reopened = LearnerProfileStore(
            language: .danish,
            defaults: defaults,
            storageKey: "words"
        )
        precondition(reopened.lemma(forKey: "gik") == "gå")
        reopened.reset()
        precondition(reopened.lemma(forKey: "gik") == nil)

        // A missed word comes back once at the end of the sitting, not again.
        let entry = { (id: String) in
            WordBookEntry(id: id, word: id, meaning: "", sentence: "", savedAt: now)
        }
        let session = WordReviewSession(entries: [entry("a"), entry("b")])
        session.answer(remembered: false)
        session.answer(remembered: true)
        precondition(session.current?.id == "a")
        session.answer(remembered: false)
        precondition(session.isFinished)
        precondition(session.rememberedCount == 1)
        precondition(session.forgottenCount == 2)

        print("Word review checks passed")
    }
}
