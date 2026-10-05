import Foundation
@testable import BabelstaarnetKit

@main
enum WordBookChecks {
    @MainActor
    static func main() {
        let suite = "WordBookChecks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let book = WordBookStore(defaults: defaults, storageKey: "book")
        let earlier = Date(timeIntervalSince1970: 1_000)
        book.save(
            key: "jo",
            word: "jo",
            meaning: "you know",
            sentence: "Og så taler hun   jo\nnorsk.",
            at: earlier
        )
        book.save(
            key: "får",
            word: "Får",
            meaning: "gets",
            sentence: "Han får en ny bil.",
            at: earlier.addingTimeInterval(10)
        )
        precondition(book.entries.map(\.id) == ["får", "jo"])
        precondition(book.entries[1].sentence == "Og så taler hun jo norsk.")

        // Saved again from a bubble that had no meaning for it: the word comes
        // back to the top, and the meaning kept before is not thrown away.
        book.save(
            key: "jo",
            word: "jo",
            meaning: "jo",
            sentence: "",
            at: earlier.addingTimeInterval(20)
        )
        precondition(book.entries.map(\.id) == ["jo", "får"])
        precondition(book.entries[0].meaning == "you know")
        precondition(book.entries[0].sentence == "Og så taler hun jo norsk.")

        // Words marked before the book existed join it without meanings, and
        // a word already in it is not added twice.
        book.adopt([
            (key: "jo", word: "jo", seenAt: earlier),
            (key: "masse", word: "masse", seenAt: earlier.addingTimeInterval(5))
        ])
        precondition(book.entries.map(\.id) == ["jo", "får", "masse"])
        precondition(book.entries[2].meaning.isEmpty)
        book.setMeaning("lot", for: "masse")

        let reopened = WordBookStore(defaults: defaults, storageKey: "book")
        precondition(reopened.entries == book.entries)

        let csv = reopened.csv()
        precondition(csv.hasPrefix("word,dictionary form,meaning,sentence,saved\n"))
        precondition(csv.contains("\"masse\",\"\",\"lot\",\"\","))

        reopened.remove("får")
        precondition(!reopened.contains("får"))
        precondition(
            WordBookStore(defaults: defaults, storageKey: "book")
                .entries.count == 2
        )

        print("Word book checks passed")
    }
}
