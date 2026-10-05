import SwiftUI

/// The words the reader asked about while reading, with what each meant and
/// the sentence it was met in.
public struct WordBookView: View {
    public static let windowID = "word-book"

    @ObservedObject var model: AppModel
    @ObservedObject private var book: WordBookStore
    // Plain published state rather than `@State`, which this package's
    // command-line toolchain cannot expand.
    @StateObject private var query = Query()

    public init(model: AppModel) {
        self.model = model
        self.book = model.wordBook
    }

    @MainActor
    private final class Query: ObservableObject {
        @Published var search = ""
        @Published var filter = Filter.all
        @Published var review: WordReviewSession?
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case learning = "Learning"
        case known = "Known"

        var id: Self { self }
    }

    public var body: some View {
        Group {
            if let review = query.review {
                WordReviewView(model: model, session: review) {
                    query.review = nil
                }
            } else {
                list
            }
        }
        .frame(minWidth: 460, minHeight: 360)
        .task {
            await model.fillMissingWordBookMeanings()
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if book.entries.isEmpty {
                emptyState
            } else if visibleEntries.isEmpty {
                Text("No words match.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleEntries) { entry in
                    row(entry)
                }
                .listStyle(.inset)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Search", text: $query.search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Picker("Show", selection: $query.filter) {
                ForEach(Filter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            Text(countLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button("Export…") {
                model.exportWordBook()
            }
            .disabled(book.entries.isEmpty)

            let due = model.dueWordBookEntries()
            Button(due.isEmpty ? "Review" : "Review (\(due.count))") {
                query.review = WordReviewSession(entries: due)
            }
            .buttonStyle(.borderedProminent)
            .disabled(due.isEmpty)
            .help(
                due.isEmpty
                    ? "No word is due. Words come back on their own as their time comes round."
                    : "Go through the words whose time has come round"
            )
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Your word book is empty")
                .font(.headline)
            Text(
                "While reading, press \(model.bubbleShortcutHints[1].key) (Don’t know) or \(model.bubbleShortcutHints[2].key) (Pin) on a word, and it is kept here with its meaning and the sentence you met it in."
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ entry: WordBookEntry) -> some View {
        let familiarity = model.wordBookFamiliarity(for: entry)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.word)
                        .font(.system(size: 14, weight: .semibold))
                        .textSelection(.enabled)
                    if let lemma = entry.lemma {
                        Text("(\(lemma))")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    Text(entry.meaning.isEmpty ? "…" : entry.meaning)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if !entry.sentence.isEmpty {
                    Text(entry.sentence)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(familiarity.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        .quaternary.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                Text(dueLabel(for: entry))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Button {
                model.speakWordBookEntry(entry)
            } label: {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .help("Say it")
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Say It") {
                model.speakWordBookEntry(entry)
            }
            Button("I Know This Now") {
                model.markWordBookEntryKnown(entry)
            }
            Divider()
            Button("Remove from Word Book", role: .destructive) {
                model.removeWordBookEntry(entry)
            }
        }
    }

    private func dueLabel(for entry: WordBookEntry) -> String {
        let due = model.wordBookDueDate(for: entry)
        guard due > Date() else {
            return "Due now"
        }
        return "Next " + due.formatted(.relative(presentation: .named))
    }

    private var countLabel: String {
        let count = book.entries.count
        return "\(count) \(count == 1 ? "word" : "words")"
    }

    private var visibleEntries: [WordBookEntry] {
        let search = query.search.trimmingCharacters(in: .whitespaces)
        return book.entries.filter { entry in
            switch query.filter {
            case .all:
                break
            case .learning:
                guard !isKnown(entry) else { return false }
            case .known:
                guard isKnown(entry) else { return false }
            }
            guard !search.isEmpty else {
                return true
            }
            return entry.word.localizedCaseInsensitiveContains(search)
                || entry.meaning.localizedCaseInsensitiveContains(search)
                || entry.sentence.localizedCaseInsensitiveContains(search)
        }
    }

    private func isKnown(_ entry: WordBookEntry) -> Bool {
        switch model.wordBookFamiliarity(for: entry) {
        case .familiar, .established:
            return true
        case .new, .learning:
            return false
        }
    }
}
