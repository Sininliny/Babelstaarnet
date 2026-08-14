import CoreGraphics
import Foundation
@testable import BabelstaarnetKit

@main
enum OCRTextQualityPolicyChecks {
    static func main() {
        for valid in [
            "medlemstype/betalingsperiode",
            "menneskerettighedsorganisation",
            "LGBT+",
            "A2B",
            "e-Boks",
            "iPhone",
            "qigong",
            "Qeqertarsuaq"
        ] {
            precondition(OCRTextQualityPolicy(language: .danish).isPlausibleWord(valid))
        }

        for corrupted in [
            "mJdlBrnStypibelHllnprædode",
            "kaDOJ",
            "lorsfinqsgruppen"
        ] {
            precondition(!OCRTextQualityPolicy(language: .danish).isPlausibleWord(corrupted))
        }

        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let clean = textRegion(
            words: ["Har", "du", "skiftet", "medlemstype/betalingsperiode"],
            y: 100,
            screen: screen
        )
        let broken = textRegion(
            words: ["mJdlBrnStypibelHllnprædode", "kaDOJ", "bort"],
            y: 140,
            screen: screen
        )
        precondition(
            OCRTextQualityPolicy(language: .danish).plausibleRegions(
                from: [clean, broken]
            ) == [clean]
        )

        // A colour failure usually garbles one word, not the line. Losing the
        // line would take the word under the pointer with it, so the readable
        // part has to survive.
        let mostlyReadable = textRegion(
            words: ["Månedlig", "leje", "kaDOJ", "møblering"],
            y: 180,
            screen: screen
        )
        let salvaged = OCRTextQualityPolicy(language: .danish).plausibleRegions(
            from: [mostlyReadable]
        )
        precondition(salvaged.count == 1)
        precondition(salvaged[0].id == mostlyReadable.id)
        precondition(
            salvaged[0].sourceText == "Månedlig leje møblering"
        )
        precondition(salvaged[0].words.count == 3)
        precondition(
            salvaged[0].words.allSatisfy {
                mostlyReadable.frame.contains($0.frame)
            }
        )
        precondition(
            salvaged[0].frame.width <= mostlyReadable.frame.width
        )

        // Dropping a word at the end really does tighten the line frame, which
        // is what keeps hover hit-testing off the discarded area.
        let trailingNoise = textRegion(
            words: ["Månedlig", "leje", "møblering", "kaDOJ"],
            y: 260,
            screen: screen
        )
        let trimmed = OCRTextQualityPolicy(language: .danish).plausibleRegions(
            from: [trailingNoise]
        )
        precondition(trimmed.count == 1)
        precondition(
            trimmed[0].frame.maxX < trailingNoise.frame.maxX
        )

        // Half unreadable is not a garbled word, it is a garbled line.
        let halfBroken = textRegion(
            words: ["kaDOJ", "mJdlBrnStypibel", "leje", "vand"],
            y: 220,
            screen: screen
        )
        precondition(
            OCRTextQualityPolicy(language: .danish).plausibleRegions(
                from: [halfBroken]
            ).isEmpty
        )

        // The misread that produced "kidney" for a word meaning "new": OCR
        // read "nyt" as "nyL". A stray capital at the end of a lowercase word
        // is an ascender misread, and the wrong answer that follows it carries
        // no sign of being wrong.
        precondition(!OCRTextQualityPolicy(language: .danish).isPlausibleWord("nyL"))
        precondition(!OCRTextQualityPolicy(language: .danish).isPlausibleWord("ansøgningL"))
        precondition(!OCRTextQualityPolicy(language: .danish).isPlausibleWord("aB"))
        // Acronyms and names are untouched: all-uppercase is accepted above,
        // and a capital belongs at the front of a name, not the end.
        precondition(OCRTextQualityPolicy(language: .danish).isPlausibleWord("CPR"))
        precondition(OCRTextQualityPolicy(language: .danish).isPlausibleWord("CPR-kontoret"))
        precondition(OCRTextQualityPolicy(language: .danish).isPlausibleWord("København"))
        precondition(OCRTextQualityPolicy(language: .danish).isPlausibleWord("nyt"))
        precondition(OCRTextQualityPolicy(language: .danish).isPlausibleWord("iPhone"))

        print("Corrupted OCR text quality checks passed")
    }

    private static func textRegion(
        words: [String],
        y: CGFloat,
        screen: CGRect
    ) -> TextRegion {
        var x: CGFloat = 100
        let regions = words.map { word -> WordRegion in
            let width = max(CGFloat(word.count) * 8, 24)
            defer { x += width + 8 }
            return WordRegion(
                sourceText: word,
                frame: CGRect(x: x, y: y, width: width, height: 24),
                screenFrame: screen,
                displayID: 1
            )
        }
        let frame = regions.dropFirst().reduce(regions[0].frame) {
            $0.union($1.frame)
        }
        return TextRegion(
            sourceText: words.joined(separator: " "),
            frame: frame,
            screenFrame: screen,
            displayID: 1,
            words: regions
        )
    }
}
