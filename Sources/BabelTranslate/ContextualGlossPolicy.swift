import BabelCore
import Foundation
import NaturalLanguage

/// Which parts of a contextual answer are shown, and which are set aside for
/// what word-at-a-time translation already had.
///
/// The model is asked two questions side by side — every word of the sentence,
/// and the word under the pointer on its own — and the second answer is the
/// weaker one: measured on the same 31 words, the sentence glosses were right
/// 29 times and the single-word answers 26. So the sentence gloss is the
/// meaning, and the single-word answer contributes only what it alone has, the
/// dictionary form and the explanation, and only when it is about the same
/// sense. "Hun tog toget" was glossed "took" in the sentence and "train" on its
/// own, with an explanation of trains.
public struct ContextualGlossPolicy: Sendable {
    private let source: SourceLanguage
    private let target: TargetLanguage

    public init(languages: LanguagePair) {
        self.source = languages.source
        self.target = languages.target
    }

    /// The meaning to show for the word under the pointer.
    public func meaning(
        sentenceGloss: String?,
        focus: ContextualGloss.FocusedWord?
    ) -> String? {
        if let sentenceGloss, !sentenceGloss.isEmpty {
            return sentenceGloss
        }
        if let gloss = focus?.gloss, !gloss.isEmpty {
            return gloss
        }
        return nil
    }

    /// The explanation, when it can be trusted to be about the sense the
    /// sentence gloss names and to be written in the language being learned.
    public func explanation(
        for focus: ContextualGloss.FocusedWord?,
        sentenceGloss: String?
    ) -> String? {
        guard let focus, !focus.explanation.isEmpty else {
            return nil
        }
        if let sentenceGloss, !sentenceGloss.isEmpty,
           !glossesAgree(sentenceGloss, focus.gloss) {
            return nil
        }
        guard isWrittenInSourceLanguage(focus.explanation) else {
            return nil
        }
        return focus.explanation
    }

    /// Whether two short glosses name the same sense: the same word, or two
    /// forms of one — "look forward" and "looking forward to".
    ///
    /// Deliberately strict. A disagreement costs only the model's explanation,
    /// and the one shown instead is built from the sentence gloss, so it is
    /// about the right sense either way; an agreement wrongly granted shows
    /// the reader an explanation of a different word.
    func glossesAgree(_ lhs: String, _ rhs: String) -> Bool {
        let left = stems(of: lhs)
        let right = stems(of: rhs)
        guard !left.isEmpty, !right.isEmpty else {
            return false
        }
        return left.contains { word in
            right.contains { other in
                word == other
                    || (min(word.count, other.count) >= 4
                        && (word.hasPrefix(other) || other.hasPrefix(word)))
            }
        }
    }

    /// Whether `text` reads as the source language rather than the target.
    ///
    /// Asked for an explanation in Danish, the model still answered in English
    /// two times in thirty-one — "You are allowed to." — and an English
    /// sentence in the place of the Danish one teaches the reader nothing the
    /// gloss above it had not. Only the two languages in play are weighed, so
    /// a short Danish sentence is not lost to Norwegian.
    func isWrittenInSourceLanguage(_ text: String) -> Bool {
        let sourceLanguage = source.naturalLanguage
        let targetLanguage = NLLanguage(rawValue: target.code)
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [sourceLanguage, targetLanguage]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        return (hypotheses[sourceLanguage] ?? 0)
            > (hypotheses[targetLanguage] ?? 0)
    }

    private func stems(of gloss: String) -> [String] {
        gloss
            .lowercased(with: target.locale)
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count >= 3 && !target.danglingWords.contains($0) }
            .map { word in
                for suffix in ["ing", "ed", "es", "s"]
                where word.count > suffix.count + 2 && word.hasSuffix(suffix) {
                    return String(word.dropLast(suffix.count))
                }
                return word
            }
    }
}
