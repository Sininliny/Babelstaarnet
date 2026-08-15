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
    public let abbreviations: Set<String>
    /// Whether a sentence in this language opens with a capital, which is what
    /// lets a period followed by a lower-case word be read as an ordinal or an
    /// unlisted abbreviation rather than as a stop.
    public let opensWithCapital: Bool
    /// Whether a lone letter before a period is an initial.
    public let singleLetterIsInitial: Bool
    public let stops: Set<Character>
    public let closers: Set<Character>
    public let openers: Set<Character>

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
    public let recognitionLanguages: [String]
    /// The `.traineddata` name Tesseract knows this language by.
    public let tesseractCode: String
    /// Characters that are strong enough evidence on their own — Danish æøå
    /// appear in essentially no neighbouring language's ordinary spelling.
    public let distinctiveCharacters: CharacterSet
    public let minimumConfidence: Double
    public let minimumFocusedConfidence: Double
    public let confidentOtherLanguageThreshold: Double
    /// Above this length an all-lowercase word is more likely a compound than
    /// a misread, so length alone stops being suspicious.
    public let compoundWordMinimumLength: Int
    /// Whether a word in this language can end in a capital. Danish cannot,
    /// which is what makes a trailing capital a misread ascender rather than a
    /// spelling.
    public let endsWordInCapital: Bool

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
    public let suffix: String
    public let gloss: String

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
    public let code: String
    public let displayName: String
    public let localeIdentifier: String
    public let speechVoice: String
    /// Letter-by-letter foldings applied before lookup, so a table can be
    /// written in ASCII and still match "på". Applied before the general
    /// diacritic fold, which would otherwise turn ø into o and collide.
    public let letterFoldings: [Character: String]
    public let ocr: OCRLanguageHints
    public let sentenceRules: SentenceBoundaryRules
    /// Closed classes, in folded form. A word here is answered from the table
    /// rather than by the translator: asked on its own, Danish "er" comes back
    /// as "no", and once the target language stands in place of the source
    /// rather than beside it, a wrong answer is the only thing left.
    public let closedClassGlosses: [String: String]
    /// Readings a translator may legitimately return for a word that also has
    /// a curated form, so the curated form is a fallback and not a pin.
    public let acceptedGlosses: [String: Set<String>]
    public let exactGlosses: [String: String]
    public let compoundSuffixes: [CompoundSuffix]
    /// Explanations of common words, written in this language, for a reader
    /// who has no connection to a translation engine.
    public let beginnerGlosses: [String: String]
    /// Explanations that say nothing and should be discarded, in folded form.
    public let vacuousExplanations: Set<String>
    /// High-frequency structural words a reader is assumed to already know,
    /// so the frame of the sentence survives from the first scan. Explicit
    /// learner feedback always overrides this prior.
    public let structuralWords: Set<String>
    /// How this language says "means X", used when there is no bridge to show.
    public let meansPhrase: @Sendable (String) -> String

    /// Built once. These are read per word — `normalized` and `lowercased` sit
    /// inside the OCR and bridge loops — and rebuilding a `Locale` from its
    /// identifier on every one of those calls is what the services used to
    /// avoid by holding a `static let`.
    public let locale: Locale
    public let naturalLanguage: NLLanguage

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
        self.locale = Locale(identifier: localeIdentifier)
        self.naturalLanguage = NLLanguage(rawValue: code)
    }

    /// The form every table in this pack is keyed by: lower-cased, folded
    /// through `letterFoldings`, then stripped of any remaining diacritics.
    ///
    /// One pass, character by character, rather than one full-string
    /// replacement per folding. That is not only cheaper — it is the only way
    /// the result is defined at all. Replacing sequentially means each folding
    /// sees what the previous one produced, and `letterFoldings` is a
    /// Dictionary, whose iteration order Swift does not promise and which in
    /// fact varies between runs of the same binary. Danish gets away with it
    /// because none of "ae", "oe", "aa" contains æ, ø, or å; a pack folding
    /// ß→ss while also mapping s would not, and would fold differently on
    /// different launches.
    public func folded(_ value: String) -> String {
        let lowercased = value.lowercased()
        var folded = ""
        folded.reserveCapacity(lowercased.count)
        for character in lowercased {
            if let replacement = letterFoldings[character] {
                folded += replacement
            } else {
                folded.append(character)
            }
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
