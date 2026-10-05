import BabelCore
import BabelTranslate
import Foundation

/// A sentence, as the contextual glosser is asked about it.
struct ContextualGlossRequest: Equatable, Sendable {
    let sentence: String
    /// Each distinct word of the sentence once, in reading order, as printed.
    let words: [String]
    /// The word under the pointer, as printed, without its punctuation.
    let focus: String

    /// The sentence around `word`, and every word in it.
    init?(
        containing word: WordRegion,
        in region: TextRegion,
        among regions: [TextRegion],
        language: SourceLanguage,
        assembly: SentenceAssemblyPolicy
    ) {
        let sentence = assembly.sentence(
            containing: word,
            in: region,
            among: regions
        ).text
        let focus = word.sourceText.trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters)
        )
        guard !sentence.isEmpty, !focus.isEmpty else {
            return nil
        }
        var seen = Set<String>()
        var words: [String] = []
        let source = sentence as NSString
        for match in Self.wordExpression.matches(
            in: sentence,
            range: NSRange(location: 0, length: source.length)
        ) {
            let token = source.substring(with: match.range)
            // Numbers have nothing to gloss, and every word asked about costs
            // time the reader spends waiting.
            guard token.contains(where: \.isLetter),
                  seen.insert(language.normalized(token)).inserted else {
                continue
            }
            words.append(token)
        }
        self.sentence = sentence
        self.words = words
        self.focus = focus
    }

    private static let wordExpression = try! NSRegularExpression(
        pattern: #"[\p{L}\p{N}]+(?:['’-][\p{L}\p{N}]+)*"#
    )
}

/// What the contextual glosser said about a sentence, once it can be shown.
struct ContextualGlossAnswer: Sendable {
    /// The gloss of every word of the sentence, keyed by its normalized form.
    let glossesByWord: [String: String]
    let focusKey: String
    /// The explanation of the word under the pointer, when the policy trusts
    /// it; otherwise the explanation shown is the one built as before.
    let explanation: String?
}

/// Asks the contextual glosser about the sentence under the pointer, one
/// request at a time, and remembers the answers.
///
/// A reader moving along a line produces a scan for nearly every word, and
/// each would be a second or so of model time. So only one request is ever in
/// flight, and a newer one replaces any that is still waiting rather than
/// queueing behind it: the pointer has moved, and the answer it was waiting
/// for is no longer anybody's question. Answers are kept by sentence, so the
/// rest of a line costs nothing once its first word has been asked about —
/// only the explanation, which is per word, is asked for again.
@MainActor
final class ContextualGlossCoordinator {
    private let service: ContextualGlossService
    private let policy: ContextualGlossPolicy
    private let language: SourceLanguage
    private let onFailure: (Error) -> Void

    private let glossesBySentence = BoundedCache<String, [String: String]>(
        capacity: 256
    )
    private let focusBySentenceAndWord = BoundedCache<
        String, ContextualGloss.FocusedWord
    >(capacity: 1_024)

    private var running: Task<Void, Never>?
    private var waiting: (ContextualGlossRequest, @MainActor () -> Void)?
    /// Failures since the last answer. One failure used to switch the model
    /// off until the app was relaunched, so a single sentence it could not
    /// answer left the reader on word-at-a-time translation for the rest of
    /// the day, with nothing on screen saying why the meanings had got worse.
    private var consecutiveFailures = 0
    private static let failuresBeforeGivingUp = 3

    /// Whether the worker has failed often enough in a row that a session
    /// should stop paying for a model that will not answer. Cleared when
    /// reading starts again and when engines are checked.
    var hasFailed: Bool {
        consecutiveFailures >= Self.failuresBeforeGivingUp
    }

    init(
        service: ContextualGlossService,
        languages: LanguagePair,
        onFailure: @escaping (Error) -> Void
    ) {
        self.service = service
        self.policy = ContextualGlossPolicy(languages: languages)
        self.language = languages.source
        self.onFailure = onFailure
    }

    /// The answer for `request`, if everything it needs has been asked before.
    func cachedAnswer(
        for request: ContextualGlossRequest
    ) -> ContextualGlossAnswer? {
        let focusKey = language.normalized(request.focus)
        guard let glosses = glossesBySentence[request.sentence],
              let focus = focusBySentenceAndWord[
                focusCacheKey(request.sentence, focusKey)
              ] else {
            return nil
        }
        return ContextualGlossAnswer(
            glossesByWord: glosses,
            focusKey: focusKey,
            explanation: policy.explanation(
                for: focus,
                sentenceGloss: glosses[focusKey]
            )
        )
    }

    /// Asks for whatever `request` still lacks, and calls `answered` once it
    /// can be served from `cachedAnswer(for:)`. A request replaced by a newer
    /// one before it was sent is never answered.
    func ask(
        _ request: ContextualGlossRequest,
        answered: @escaping @MainActor () -> Void
    ) {
        guard !hasFailed, service.isInstalled else {
            return
        }
        if cachedAnswer(for: request) != nil {
            answered()
            return
        }
        waiting = (request, answered)
        startNextIfIdle()
    }

    /// Drops whatever is waiting. The request already sent is left to finish,
    /// since the worker cannot be interrupted mid-answer without restarting.
    func cancelWaiting() {
        waiting = nil
    }

    func resetFailure() {
        consecutiveFailures = 0
    }

    private func startNextIfIdle() {
        guard running == nil, let (request, answered) = waiting else {
            return
        }
        waiting = nil

        let focusKey = language.normalized(request.focus)
        let hasGlosses = glossesBySentence[request.sentence] != nil
        let hasFocus = focusBySentenceAndWord[
            focusCacheKey(request.sentence, focusKey)
        ] != nil
        let words = hasGlosses ? [] : request.words
        let focus = hasFocus ? nil : request.focus

        running = Task { [weak self, service] in
            let result: Result<ContextualGloss, Error>
            do {
                result = .success(
                    try await service.gloss(
                        sentence: request.sentence,
                        words: words,
                        focus: focus
                    )
                )
            } catch {
                result = .failure(error)
            }
            guard let self else {
                return
            }
            self.running = nil
            switch result {
            case let .success(gloss):
                self.consecutiveFailures = 0
                self.remember(
                    gloss,
                    words: words,
                    sentence: request.sentence,
                    focusKey: focus == nil ? nil : focusKey
                )
                if self.cachedAnswer(for: request) != nil {
                    answered()
                }
            case let .failure(error):
                self.consecutiveFailures += 1
                if self.hasFailed {
                    self.waiting = nil
                    self.onFailure(error)
                    return
                }
            }
            self.startNextIfIdle()
        }
    }

    private func remember(
        _ gloss: ContextualGloss,
        words: [String],
        sentence: String,
        focusKey: String?
    ) {
        if !words.isEmpty {
            var byWord: [String: String] = [:]
            for (word, gloss) in zip(words, gloss.glosses) where !gloss.isEmpty {
                byWord[language.normalized(word)] = gloss
            }
            glossesBySentence[sentence] = byWord
        }
        if let focusKey {
            // Stored even when empty, so a word the model had nothing to say
            // about is not asked about again every time the pointer rests on
            // it; the policy turns an empty answer into no explanation.
            focusBySentenceAndWord[focusCacheKey(sentence, focusKey)] =
                gloss.focus ?? ContextualGloss.FocusedWord(
                    gloss: "",
                    lemma: "",
                    explanation: ""
                )
        }
    }

    private func focusCacheKey(_ sentence: String, _ focusKey: String) -> String {
        sentence + "\u{1F}" + focusKey
    }
}
