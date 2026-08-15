import Foundation

/// The language that fills the gaps: the one the reader already has, which
/// stands in for the words of the source language they cannot read yet.
///
/// Thin by design. The source language carries the sentence and the chrome, so
/// what is left here is what the crutch itself needs — a voice, a dictionary,
/// and enough about its own function words to trim a gloss without cutting it
/// mid-phrase.
public struct TargetLanguage: Sendable {
    public let code: String
    public let displayName: String
    public let localeIdentifier: String
    public let speechVoice: String
    /// Function words a gloss must not be left dangling on. Cutting "a place
    /// where people live in" at the limit leaves a phrase that reads as
    /// unfinished, so the cut walks back past these.
    public let danglingWords: Set<String>
    /// Whether the system dictionary can define words in this language, which
    /// is what decides if a fuller sense is available beyond the translation.
    public let hasSystemDictionary: Bool

    public let locale: Locale

    public init(
        code: String,
        displayName: String,
        localeIdentifier: String,
        speechVoice: String,
        danglingWords: Set<String> = [],
        hasSystemDictionary: Bool = false
    ) {
        self.code = code
        self.displayName = displayName
        self.localeIdentifier = localeIdentifier
        self.speechVoice = speechVoice
        self.danglingWords = danglingWords
        self.hasSystemDictionary = hasSystemDictionary
        self.locale = Locale(identifier: localeIdentifier)
    }
}

/// What the reader is reading and what they are reading it with.
///
/// Everything language-specific in the app is reachable from one of these two
/// halves, and nothing outside this directory should name a language directly.
public struct LanguagePair: Sendable {
    public var source: SourceLanguage
    public var target: TargetLanguage

    public init(source: SourceLanguage, target: TargetLanguage) {
        self.source = source
        self.target = target
    }
}
