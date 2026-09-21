import Foundation
@testable import BabelTranslate
@testable import LanguageDanish

@main
enum ContextualGlossPolicyChecks {
    static func main() {
        let policy = ContextualGlossPolicy(languages: .danishToEnglish)

        // The sentence gloss is the meaning; the single-word answer only
        // stands in when the sentence gave nothing for the word.
        let took = ContextualGloss.FocusedWord(
            gloss: "train",
            lemma: "tog",
            explanation: "Et tog er et køretøj, der transporterer mange mennesker."
        )
        precondition(
            policy.meaning(sentenceGloss: "took", focus: took) == "took"
        )
        precondition(
            policy.meaning(sentenceGloss: "", focus: took) == "train"
        )
        precondition(policy.meaning(sentenceGloss: nil, focus: nil) == nil)

        // "Hun tog toget": an explanation of trains is not an explanation of
        // the word that meant "took".
        precondition(
            policy.explanation(for: took, sentenceGloss: "took") == nil
        )

        // Two forms of one sense agree.
        let lookForward = ContextualGloss.FocusedWord(
            gloss: "look forward",
            lemma: "glæde",
            explanation: "At være glad for noget, der skal ske."
        )
        precondition(
            policy.explanation(
                for: lookForward,
                sentenceGloss: "looking forward"
            ) == lookForward.explanation
        )
        precondition(policy.glossesAgree("the municipality", "municipality"))
        precondition(policy.glossesAgree("gets", "gets, receives"))
        precondition(!policy.glossesAgree("doing", "makes"))
        // A shared function word is not a shared sense.
        precondition(!policy.glossesAgree("to the bill", "to the roof"))

        // An explanation that came back in English is set aside.
        let english = ContextualGloss.FocusedWord(
            gloss: "may",
            lemma: "må",
            explanation: "You are allowed to do something."
        )
        precondition(
            policy.explanation(for: english, sentenceGloss: "may") == nil
        )
        precondition(
            policy.isWrittenInSourceLanguage(
                "Det er den offentlige myndighed i en by eller et område."
            )
        )

        // With no sentence gloss to compare against, a Danish explanation is
        // kept.
        let sheep = ContextualGloss.FocusedWord(
            gloss: "sheep",
            lemma: "får",
            explanation: "Små, almindelige husdyr, der lever af græs."
        )
        precondition(
            policy.explanation(for: sheep, sentenceGloss: nil)
                == sheep.explanation
        )

        print("Contextual gloss policy checks passed")
    }
}
