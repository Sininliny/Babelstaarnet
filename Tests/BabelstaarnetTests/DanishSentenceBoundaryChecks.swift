import Foundation
@testable import BabelstaarnetKit

@main
enum DanishSentenceBoundaryChecks {
    static func main() {
        // A line that runs to a stop, and one that only wrapped.
        precondition(
            SourceLanguage.danish.sentenceBoundary.endsSentence(
                "ledelse og lige adgang til mobilitetsmidler."
            )
        )
        precondition(
            !SourceLanguage.danish.sentenceBoundary.endsSentence(
                "Det kunne fx være oplysningskampagner, støtte til"
            )
        )
        precondition(
            SourceLanguage.danish.sentenceBoundary.endsSentence("Hvem tøvede?")
        )
        precondition(
            SourceLanguage.danish.sentenceBoundary.endsSentence("Han sagde “nej.”")
        )

        // Danish writes ordinals and dates with a period, and the sentence
        // carries on straight through them.
        precondition(
            !SourceLanguage.danish.sentenceBoundary.endsSentence(
                "Der er ansøgningsfrist den 15."
            )
        )
        precondition(
            SourceLanguage.danish.sentenceBoundary.sentenceRanges(
                in: "Der er ansøgningsfrist den 15. september 2026."
            ).count == 1
        )
        precondition(
            SourceLanguage.danish.sentenceBoundary.sentenceRanges(
                in: "Du kan høre mere på et online infomøde 11. september kl. 13."
            ).count == 1
        )
        precondition(
            SourceLanguage.danish.sentenceBoundary.sentenceRanges(
                in: "Emnerne kan bl.a. være ligestilling. Andre emner er også"
                    + " velkomne."
            ).count == 2
        )
        precondition(
            SourceLanguage.danish.sentenceBoundary.sentenceRanges(
                in: "Se mere på www.au.dk. Fristen er fast."
            ).count == 2
        )

        let two = "Projektet er slut. Nye emner er velkomne."
        let ranges = SourceLanguage.danish.sentenceBoundary.sentenceRanges(in: two)
        precondition(ranges.count == 2, "\(ranges.count)")
        precondition(
            (two as NSString).substring(with: ranges[0])
                == "Projektet er slut.",
            (two as NSString).substring(with: ranges[0])
        )
        precondition(
            (two as NSString).substring(with: ranges[1])
                == "Nye emner er velkomne."
        )

        // The sentence a given position belongs to, which is how the bridge
        // decides what the pointed-at word is part of.
        precondition(
            (two as NSString).substring(
                with: SourceLanguage.danish.sentenceBoundary.sentenceRange(
                    in: two,
                    containing: 22
                )
            ) == "Nye emner er velkomne."
        )
        precondition(
            (two as NSString).substring(
                with: SourceLanguage.danish.sentenceBoundary.sentenceRange(
                    in: two,
                    containing: 4
                )
            ) == "Projektet er slut."
        )
        // Text with no stop at all is one sentence, which is the ordinary case
        // for a single OCR line.
        let single = "tilgængelighed i digitale læringsmiljøer, inkluderende"
        precondition(
            (single as NSString).substring(
                with: SourceLanguage.danish.sentenceBoundary.sentenceRange(
                    in: single,
                    containing: 3
                )
            ) == single
        )

        // A stop inside the line is what tells a line walk to stop walking.
        precondition(
            SourceLanguage.danish.sentenceBoundary.stopsBeforeEnd(
                "Projektet er slut. Nye emner"
            )
        )
        precondition(
            !SourceLanguage.danish.sentenceBoundary.stopsBeforeEnd("Projektet er slut.")
        )
        precondition(
            !SourceLanguage.danish.sentenceBoundary.stopsBeforeEnd("den 15. september 2026")
        )

        precondition(SourceLanguage.danish.sentenceBoundary.stopLocations(in: "").isEmpty)
        precondition(
            SourceLanguage.danish.sentenceBoundary.sentenceRanges(in: "").isEmpty
        )

        print("Danish sentence boundary checks passed")
    }
}
