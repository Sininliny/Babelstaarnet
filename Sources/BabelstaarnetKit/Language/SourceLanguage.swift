import Foundation
import NaturalLanguage

/// Where one sentence stops and the next one starts, as data rather than as
/// code.
///
/// The algorithm that reads these lives in `SentenceBoundary`; only the answers
/// are per-language. `opensWithCapital` is the one to be careful with: it is
/// the strongest signal the algorithm has, and it is simply false for a script
/// without case, so it is declared rather than assumed.
public struct SentenceBoundaryRules: Sendable {
    /// Abbreviations whose period belongs to the word, not to the sentence.
    /// Written down rather than inferred: the list is short, closed, and the
    /// cost of guessing wrong is a sentence that stops in the middle.
    public var abbreviations: Set<String>
    /// Whether a sentence in this language opens with a capital, which is what
    /// lets a period followed by a lower-case word be read as an ordinal or an
    /// unlisted abbreviation rather than as a stop.
    public var opensWithCapital: Bool
    /// Whether a lone letter before a period is an initial.
    public var singleLetterIsInitial: Bool
    public var stops: Set<Character>
    public var closers: Set<Character>
    public var openers: Set<Character>

    public init(
        abbreviations: Set<String>,
        opensWithCapital: Bool = true,
        singleLetterIsInitial: Bool = true,
        stops: Set<Character> = [".", "!", "?", "…"],
        closers: Set<Character> = ["\"", "'", "”", "’", "»", ")", "]", "}"],
        openers: Set<Character> = [
            "\"", "'", "“", "‘", "«", "(", "[", "{", "–", "—", "-"
        ]
    ) {
        self.abbreviations = abbreviations
        self.opensWithCapital = opensWithCapital
        self.singleLetterIsInitial = singleLetterIsInitial
        self.stops = stops
        self.closers = closers
        self.openers = openers
    }
}

/// What the recognition pipeline needs to know about a language.
///
/// Deliberately none of this is the *order* of that pipeline. Accurate Vision
/// leads, colour preparation is only ever a retry, and that ordering encodes a
/// measured correctness constraint rather than a tuning preference — so it
/// stays in `OCRService` where it cannot be reconfigured per language. What a
/// pack gets to say is which characters carry the language's identity and how
/// confident a classification has to be.
public struct OCRLanguageHints: Sendable {
    /// Passed to Vision, most specific first.
    public var recognitionLanguages: [String]
    /// The `.traineddata` name Tesseract knows this language by.
    public var tesseractCode: String
    /// Characters that are strong enough evidence on their own — Danish æøå
    /// appear in essentially no neighbouring language's ordinary spelling.
    public var distinctiveCharacters: CharacterSet
    public var minimumConfidence: Double
    public var minimumFocusedConfidence: Double
    public var confidentOtherLanguageThreshold: Double
    /// Above this length an all-lowercase word is more likely a compound than
    /// a misread, so length alone stops being suspicious.
    public var compoundWordMinimumLength: Int
    /// Whether a word in this language can end in a capital. Danish cannot,
    /// which is what makes a trailing capital a misread ascender rather than a
    /// spelling.
    public var endsWordInCapital: Bool

    public init(
        recognitionLanguages: [String],
        tesseractCode: String,
        distinctiveCharacters: CharacterSet,
        minimumConfidence: Double = 0.2,
        minimumFocusedConfidence: Double = 0.1,
        confidentOtherLanguageThreshold: Double = 0.65,
        compoundWordMinimumLength: Int = 10,
        endsWordInCapital: Bool = false
    ) {
        self.recognitionLanguages = recognitionLanguages
        self.tesseractCode = tesseractCode
        self.distinctiveCharacters = distinctiveCharacters
        self.minimumConfidence = minimumConfidence
        self.minimumFocusedConfidence = minimumFocusedConfidence
        self.confidentOtherLanguageThreshold =
            confidentOtherLanguageThreshold
        self.compoundWordMinimumLength = compoundWordMinimumLength
        self.endsWordInCapital = endsWordInCapital
    }
}

/// A compound ending and the target-language word it becomes, so an unknown
/// compound can still be read from its tail.
public struct CompoundSuffix: Sendable {
    public var suffix: String
    public var gloss: String

    public init(suffix: String, gloss: String) {
        self.suffix = suffix
        self.gloss = gloss
    }
}

/// The language being learned: the one on screen, the one the bubbles keep,
/// and the one the app's own explanatory chrome is written in.
///
/// Chrome sits here rather than on `TargetLanguage` because that is what the
/// app does today — the reader is shown "Betyder “…”." in Danish while English
/// fills the gaps. Whether the chrome should instead follow the reader's own
/// language is a product decision, not a refactoring one.
public struct SourceLanguage: Sendable {
    public var code: String
    public var displayName: String
    public var localeIdentifier: String
    public var speechVoice: String
    /// Letter-by-letter foldings applied before lookup, so a table can be
    /// written in ASCII and still match "på". Applied before the general
    /// diacritic fold, which would otherwise turn ø into o and collide.
    public var letterFoldings: [Character: String]
    public var ocr: OCRLanguageHints
    public var sentenceRules: SentenceBoundaryRules
    /// Closed classes, in folded form. A word here is answered from the table
    /// rather than by the translator: asked on its own, Danish "er" comes back
    /// as "no", and once the target language stands in place of the source
    /// rather than beside it, a wrong answer is the only thing left.
    public var closedClassGlosses: [String: String]
    /// Readings a translator may legitimately return for a word that also has
    /// a curated form, so the curated form is a fallback and not a pin.
    public var acceptedGlosses: [String: Set<String>]
    public var exactGlosses: [String: String]
    public var compoundSuffixes: [CompoundSuffix]
    /// Explanations of common words, written in this language, for a reader
    /// who has no connection to a translation engine.
    public var beginnerGlosses: [String: String]
    /// Explanations that say nothing and should be discarded, in folded form.
    public var vacuousExplanations: Set<String>
    /// High-frequency structural words a reader is assumed to already know,
    /// so the frame of the sentence survives from the first scan. Explicit
    /// learner feedback always overrides this prior.
    public var structuralWords: Set<String>
    /// How this language says "means X", used when there is no bridge to show.
    public var meansPhrase: @Sendable (String) -> String

    public var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    public var naturalLanguage: NLLanguage {
        NLLanguage(rawValue: code)
    }

    public init(
        code: String,
        displayName: String,
        localeIdentifier: String,
        speechVoice: String,
        letterFoldings: [Character: String] = [:],
        ocr: OCRLanguageHints,
        sentenceRules: SentenceBoundaryRules,
        closedClassGlosses: [String: String] = [:],
        acceptedGlosses: [String: Set<String>] = [:],
        exactGlosses: [String: String] = [:],
        compoundSuffixes: [CompoundSuffix] = [],
        beginnerGlosses: [String: String] = [:],
        vacuousExplanations: Set<String> = [],
        structuralWords: Set<String> = [],
        meansPhrase: @escaping @Sendable (String) -> String
    ) {
        self.code = code
        self.displayName = displayName
        self.localeIdentifier = localeIdentifier
        self.speechVoice = speechVoice
        self.letterFoldings = letterFoldings
        self.ocr = ocr
        self.sentenceRules = sentenceRules
        self.closedClassGlosses = closedClassGlosses
        self.acceptedGlosses = acceptedGlosses
        self.exactGlosses = exactGlosses
        self.compoundSuffixes = compoundSuffixes
        self.beginnerGlosses = beginnerGlosses
        self.vacuousExplanations = vacuousExplanations
        self.structuralWords = structuralWords
        self.meansPhrase = meansPhrase
    }

    /// The form every table in this pack is keyed by: lower-cased, folded
    /// through `letterFoldings`, then stripped of any remaining diacritics.
    public func folded(_ value: String) -> String {
        var folded = value.lowercased()
        for (character, replacement) in letterFoldings {
            folded = folded.replacingOccurrences(
                of: String(character),
                with: replacement
            )
        }
        return folded
            .folding(options: [.diacriticInsensitive], locale: nil)
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(.punctuationCharacters)
            )
    }

    /// Lower-cased by this language's own casing rules, and nothing else.
    ///
    /// Separate from `normalized` because some keys are matched against text
    /// that still carries its punctuation; trimming here would stop "hus."
    /// matching the entry it was cached under.
    public func lowercased(_ value: String) -> String {
        value.lowercased(with: locale)
    }

    /// The form used to compare two words as the same word, which keeps the
    /// language's own casing rules rather than folding it to ASCII.
    public func normalized(_ value: String) -> String {
        value.lowercased(with: locale)
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(.punctuationCharacters)
            )
    }
}
