import Foundation
@testable import BabelstaarnetKit

/// Proof that the services read their rules from the pack rather than from
/// Danish.
///
/// Every assertion here is a pair: the same call, against Danish and against a
/// fabricated language whose rules disagree with Danish on exactly that point.
/// A service that quietly goes back to naming Danish itself keeps the Danish
/// half passing and fails the other one.
@main
enum LanguagePackChecks {
    /// A language that is Danish's opposite wherever a rule exists to disagree
    /// about: sentences do not open with a capital, words may end in one, it
    /// abbreviates nothing, and it folds ß rather than æøå.
    static let contrary = SourceLanguage(
        code: "qq",
        displayName: "Contrary",
        localeIdentifier: "en_US_POSIX",
        speechVoice: "qq-QQ",
        letterFoldings: ["ß": "ss"],
        ocr: OCRLanguageHints(
            recognitionLanguages: ["qq-QQ"],
            tesseractCode: "qqq",
            distinctiveCharacters: CharacterSet(charactersIn: "ß"),
            endsWordInCapital: true
        ),
        sentenceRules: SentenceBoundaryRules(
            abbreviations: [],
            opensWithCapital: false
        ),
        closedClassGlosses: ["xyz": "zzz"],
        beginnerGlosses: ["zz": "a fabricated gloss"],
        meansPhrase: { "MEANS \($0)" }
    )

    static func main() {
        checkSentenceStops()
        checkWordPlausibility()
        checkClosedClassTables()
        checkFolding()
        checkBeginnerGlosses()
        checkVocabularyPrior()
        checkChrome()
        print("Language pack checks passed")
    }

    /// A period before a lower-case word ends a sentence only where sentences
    /// are not required to open with a capital.
    private static func checkSentenceStops() {
        let text = "abc. def"
        precondition(
            SourceLanguage.danish.sentenceBoundary
                .stopLocations(in: text)
                .isEmpty
        )
        precondition(
            contrary.sentenceBoundary.stopLocations(in: text) == [4]
        )

        // The abbreviation list is the pack's, so a language that lists
        // nothing stops where Danish keeps reading. The following word is
        // capitalised deliberately: a digit or a lower-case word would be
        // settled by the rules above before the list is ever consulted.
        let abbreviated = "Kom kl. Torsdag"
        precondition(
            !SourceLanguage.danish.sentenceBoundary
                .stopsBeforeEnd(abbreviated)
        )
        precondition(
            contrary.sentenceBoundary.stopsBeforeEnd(abbreviated)
        )
    }

    /// A trailing capital is a misread only where a word cannot end in one.
    private static func checkWordPlausibility() {
        precondition(
            !OCRTextQualityPolicy(language: .danish)
                .isPlausibleWord("nyL")
        )
        precondition(
            OCRTextQualityPolicy(language: contrary)
                .isPlausibleWord("nyL")
        )
    }

    /// A closed-class word is answered from the pack's table, never from a
    /// table the service carries itself.
    private static func checkClosedClassTables() {
        let danish = TranslationQualityService(language: .danish)
        precondition(
            danish.bestTranslation(source: "er", primary: "no") == "is"
        )
        precondition(
            danish.bestTranslation(source: "på", primary: "wrong") == "on"
        )

        let other = TranslationQualityService(language: contrary)
        precondition(
            other.bestTranslation(source: "xyz", primary: "wrong") == "zzz"
        )
        // Danish's table must not be reachable from another language.
        precondition(
            other.bestTranslation(source: "er", primary: "no") == "no"
        )
    }

    /// Table keys are folded by the pack's own letter rules.
    private static func checkFolding() {
        precondition(SourceLanguage.danish.folded("på") == "paa")
        precondition(SourceLanguage.danish.folded("VÆRE") == "vaere")
        precondition(contrary.folded("Straße") == "strasse")
        // Danish's foldings are not applied to another language.
        precondition(contrary.folded("på") == "pa")
    }

    private static func checkBeginnerGlosses() {
        precondition(
            BeginnerGlossService(language: .danish)
                .localExplanation(for: "  Og! ") != nil
        )
        precondition(
            BeginnerGlossService(language: contrary)
                .localExplanation(for: "og") == nil
        )
        precondition(
            BeginnerGlossService(language: contrary)
                .localExplanation(for: "ZZ") == "a fabricated gloss"
        )
    }

    /// Which words a reader starts out counted as knowing is the pack's call,
    /// so a new language does not inherit Danish's head start.
    private static func checkVocabularyPrior() {
        precondition(
            VocabularyPrior.initialKnowledgeLevel(for: "og", in: .danish)
                == AdaptiveKnowledgePolicy.knownLevel
        )
        precondition(
            VocabularyPrior.initialKnowledgeLevel(for: "og", in: contrary) == 0
        )
    }

    /// The "means X" line is written in the language being read.
    private static func checkChrome() {
        let danish = AdaptiveExplanationService(language: .danish)
            .explanation(
                bridgeText: "",
                englishMeaning: "harbour",
                expandedEnglish: "",
                expandEnglish: false
            )
        precondition(danish.primaryText == "Betyder “harbour”.")

        let other = AdaptiveExplanationService(language: contrary)
            .explanation(
                bridgeText: "",
                englishMeaning: "harbour",
                expandedEnglish: "",
                expandEnglish: false
            )
        precondition(other.primaryText == "MEANS harbour")
    }
}
