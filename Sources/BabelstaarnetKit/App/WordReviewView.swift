import SwiftUI

/// One sitting of review: the words that were due when it began, in order,
/// with a forgotten word asked once more at the end.
@MainActor
final class WordReviewSession: ObservableObject {
    @Published private(set) var queue: [WordBookEntry]
    @Published private(set) var position = 0
    @Published var revealed = false
    @Published private(set) var rememberedCount = 0
    @Published private(set) var forgottenCount = 0
    private var askedAgain = Set<String>()

    init(entries: [WordBookEntry]) {
        queue = entries
    }

    var current: WordBookEntry? {
        position < queue.count ? queue[position] : nil
    }

    var isFinished: Bool {
        current == nil
    }

    /// Records the answer and moves on. A word not remembered goes to the
    /// back of the queue once, so it is seen again while it is fresh, but a
    /// word missed twice is left for its next due date rather than asked
    /// until it is guessed.
    func answer(remembered: Bool) {
        guard let entry = current else {
            return
        }
        if remembered {
            rememberedCount += 1
        } else {
            forgottenCount += 1
            if askedAgain.insert(entry.id).inserted {
                queue.append(entry)
            }
        }
        position += 1
        revealed = false
    }
}

/// A card per word: the word in the sentence it was read in, then its meaning
/// on request, then whether the reader remembered it.
///
/// Nothing here runs while reading. The bubbles still ask nothing of the
/// reader; this is for the moments they choose to open the word book.
struct WordReviewView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var session: WordReviewSession
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done") {
                    onDone()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                if !session.isFinished {
                    Text("\(min(session.position + 1, session.queue.count)) of \(session.queue.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(12)
            Divider()

            if let entry = session.current {
                card(entry)
            } else {
                finished
            }
        }
    }

    private func card(_ entry: WordBookEntry) -> some View {
        VStack(spacing: 14) {
            Spacer()

            HStack(spacing: 8) {
                Text(entry.word)
                    .font(.system(size: 30, weight: .semibold))
                Button {
                    model.speakWordBookEntry(entry)
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.borderless)
                .help("Say it")
            }

            if !entry.sentence.isEmpty {
                Text(Self.sentence(entry.sentence, highlighting: entry.word))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            if session.revealed {
                VStack(spacing: 4) {
                    Text(entry.meaning.isEmpty ? "No meaning saved" : entry.meaning)
                        .font(.system(size: 18))
                    if let lemma = entry.lemma {
                        Text("Dictionary form: \(lemma)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }

            Spacer()

            if session.revealed {
                HStack(spacing: 12) {
                    Button {
                        answer(entry, remembered: false)
                    } label: {
                        Text("Didn’t know  2")
                            .frame(minWidth: 120)
                    }
                    .keyboardShortcut("2", modifiers: [])

                    Button {
                        answer(entry, remembered: true)
                    } label: {
                        Text("Knew it  1")
                            .frame(minWidth: 120)
                    }
                    .keyboardShortcut("1", modifiers: [])
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Button {
                    session.revealed = true
                } label: {
                    Text("Show meaning  Space")
                        .frame(minWidth: 180)
                }
                .keyboardShortcut(.space, modifiers: [])
            }
        }
        .controlSize(.large)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if model.autoSpeak {
                model.speakWordBookEntry(entry)
            }
        }
        .id(session.position)
    }

    private var finished: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("Nothing more to review")
                .font(.headline)
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Back to Word Book") {
                onDone()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summary: String {
        let remembered = session.rememberedCount
        let forgotten = session.forgottenCount
        guard remembered + forgotten > 0 else {
            return "No word in the book is due. Words come back on their own as their time comes round."
        }
        return "You knew \(remembered) and missed \(forgotten). Words you knew come back later each time; the ones you missed come back sooner, and stay in English while you read until you know them."
    }

    private func answer(_ entry: WordBookEntry, remembered: Bool) {
        model.reviewWordBookEntry(entry, remembered: remembered)
        session.answer(remembered: remembered)
    }

    /// The sentence with the word in bold, so the card shows the word where
    /// it was met rather than on its own.
    static func sentence(
        _ sentence: String,
        highlighting word: String
    ) -> AttributedString {
        var text = AttributedString(sentence)
        if let range = text.range(
            of: word,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            text[range].font = .system(size: 13, weight: .semibold)
            text[range].foregroundColor = .primary
        }
        return text
    }
}
