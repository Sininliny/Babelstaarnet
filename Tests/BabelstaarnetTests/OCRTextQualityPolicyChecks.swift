import CoreGraphics
import Foundation

@main
enum OCRTextQualityPolicyChecks {
    static func main() {
        for valid in [
            "medlemstype/betalingsperiode",
            "menneskerettighedsorganisation",
            "LGBT+",
            "A2B",
            "e-Boks",
            "iPhone"
        ] {
            precondition(OCRTextQualityPolicy.isPlausibleWord(valid))
        }

        for corrupted in [
            "mJdlBrnStypibelHllnprædode",
            "kaDOJ"
        ] {
            precondition(!OCRTextQualityPolicy.isPlausibleWord(corrupted))
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
            OCRTextQualityPolicy.plausibleRegions(
                from: [clean, broken]
            ) == [clean]
        )

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
