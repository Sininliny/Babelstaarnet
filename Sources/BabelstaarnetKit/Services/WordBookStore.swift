import Foundation

/// A word the reader set aside to come back to, with what it meant where they
/// met it.
struct WordBookEntry: Codable, Equatable, Identifiable, Sendable {
    /// The word's stored form, the same key the learner profile uses.
    let id: String
    /// The word as it was printed where the reader met it.
    var word: String
    /// The meaning the bubble showed. Empty for a word saved before meanings
    /// were kept, until one is filled in.
    var meaning: String
    /// The sentence the word was read in.
    var sentence: String
    var savedAt: Date
    /// The word's dictionary form, when the contextual glosser gave one that
    /// differs from the word: "gå" for "gik".
    var lemma: String? = nil
}

/// The words the reader asked about: every word marked "Don't know" and every
/// word whose bubble was pinned.
///
/// The learner profile already remembered those words, but only as numbers
/// behind the bubble — how often a word was seen, how sure the reader was —
/// with no meaning attached and nowhere to look at them. This is the list the
/// reader can open, kept beside the profile rather than inside it, so the
/// profile's archive format does not change.
@MainActor
final class WordBookStore: ObservableObject {
    static let maximumEntryCount = 5_000
    private static let maximumSentenceLength = 400

    @Published private(set) var entries: [WordBookEntry] = []

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "wordBook.entries"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(
               [WordBookEntry].self,
               from: data
           ) {
            entries = decoded
        }
    }

    func contains(_ key: String) -> Bool {
        entries.contains { $0.id == key }
    }

    /// Saves `word`, or brings it back to the top with the newer meaning and
    /// sentence when it is already there.
    func save(
        key: String,
        word: String,
        meaning: String,
        sentence: String,
        lemma: String? = nil,
        at date: Date = Date()
    ) {
        guard !key.isEmpty else {
            return
        }
        let meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = String(
            sentence
                .replacingOccurrences(
                    of: #"\s+"#,
                    with: " ",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.maximumSentenceLength)
        )
        // A bubble whose meaning is the word itself had nothing to say about
        // it, and that is not worth writing down over a meaning kept before.
        let usefulMeaning = meaning.caseInsensitiveCompare(word) == .orderedSame
            ? ""
            : meaning
        var entry = entries.first { $0.id == key }
            ?? WordBookEntry(
                id: key,
                word: word,
                meaning: "",
                sentence: "",
                savedAt: date
            )
        entry.word = word
        if !usefulMeaning.isEmpty {
            entry.meaning = usefulMeaning
        }
        if !sentence.isEmpty {
            entry.sentence = sentence
        }
        if let lemma, !lemma.isEmpty {
            entry.lemma = lemma
        }
        entry.savedAt = date
        entries.removeAll { $0.id == key }
        entries.insert(entry, at: 0)
        if entries.count > Self.maximumEntryCount {
            entries.removeLast(entries.count - Self.maximumEntryCount)
        }
        persist()
    }

    /// Adds words that are not in the book yet, at the end and without
    /// meanings. Used once, for words marked "Don't know" before there was a
    /// book to put them in.
    func adopt(_ words: [(key: String, word: String, seenAt: Date)]) {
        var known = Set(entries.map(\.id))
        var added = false
        for candidate in words where known.insert(candidate.key).inserted {
            entries.append(
                WordBookEntry(
                    id: candidate.key,
                    word: candidate.word,
                    meaning: "",
                    sentence: "",
                    savedAt: candidate.seenAt
                )
            )
            added = true
        }
        guard added else {
            return
        }
        entries.sort { $0.savedAt > $1.savedAt }
        if entries.count > Self.maximumEntryCount {
            entries.removeLast(entries.count - Self.maximumEntryCount)
        }
        persist()
    }

    func setMeaning(_ meaning: String, for key: String) {
        guard let index = entries.firstIndex(where: { $0.id == key }),
              !meaning.isEmpty else {
            return
        }
        entries[index].meaning = meaning
        persist()
    }

    func remove(_ key: String) {
        entries.removeAll { $0.id == key }
        persist()
    }

    func removeAll() {
        entries.removeAll()
        defaults.removeObject(forKey: storageKey)
    }

    /// The book as a spreadsheet, for flash-card apps and anything else that
    /// reads CSV.
    func csv() -> String {
        func field(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        var lines = ["word,dictionary form,meaning,sentence,saved"]
        for entry in entries {
            lines.append(
                [
                    field(entry.word),
                    field(entry.lemma ?? ""),
                    field(entry.meaning),
                    field(entry.sentence),
                    formatter.string(from: entry.savedAt)
                ].joined(separator: ",")
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
