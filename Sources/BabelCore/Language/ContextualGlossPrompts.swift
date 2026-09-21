import Foundation

/// What a local language model is told when it is asked for the sense a word
/// has in its sentence, written in the language being learned.
///
/// The instructions belong to the language pack rather than to the worker for
/// the same reason every other table does: the worker is a capability and names
/// no language. They are written in the source language itself because written
/// in English, the model answered a request for an explanation in the source
/// language in English about one time in three.
public struct ContextualGlossPrompts: Sendable, Encodable, Equatable {
    /// Asks for one short target-language gloss per numbered word, in the
    /// sense it has in the sentence, as `N. word = gloss` lines.
    public let glossInstructions: String
    /// Asks, for a single word, for its gloss, its dictionary form, and a short
    /// explanation of it in the source language, as three labelled lines.
    public let explainInstructions: String
    public let sentenceLabel: String
    public let wordsLabel: String
    public let answerLabel: String
    public let lemmaLabel: String
    public let explanationLabel: String
    /// A sentence and a word in it that any working model glosses, so that a
    /// readiness check proves the model answers rather than only that it loads.
    public let checkSentence: String
    public let checkWord: String

    public init(
        glossInstructions: String,
        explainInstructions: String,
        sentenceLabel: String,
        wordsLabel: String,
        answerLabel: String,
        lemmaLabel: String,
        explanationLabel: String,
        checkSentence: String,
        checkWord: String
    ) {
        self.glossInstructions = glossInstructions
        self.explainInstructions = explainInstructions
        self.sentenceLabel = sentenceLabel
        self.wordsLabel = wordsLabel
        self.answerLabel = answerLabel
        self.lemmaLabel = lemmaLabel
        self.explanationLabel = explanationLabel
        self.checkSentence = checkSentence
        self.checkWord = checkWord
    }

    enum CodingKeys: String, CodingKey {
        case glossInstructions = "gloss_instructions"
        case explainInstructions = "explain_instructions"
        case sentenceLabel = "sentence_label"
        case wordsLabel = "words_label"
        case answerLabel = "answer_label"
        case lemmaLabel = "lemma_label"
        case explanationLabel = "explanation_label"
        case checkSentence = "check_sentence"
        case checkWord = "check_word"
    }
}
