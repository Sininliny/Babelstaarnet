import CoreGraphics
import Foundation
@testable import BabelCore
@testable import BabelOCR
@testable import BabelTranslate
@testable import BabelLexicon
@testable import BabelSpeech
@testable import LanguageDanish
@testable import BabelstaarnetKit

@main
enum OCRRoutingPolicyChecks {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let word = WordRegion(
            sourceText: "dansk",
            frame: CGRect(x: 100, y: 100, width: 55, height: 24),
            screenFrame: screen,
            displayID: 1
        )
        let region = TextRegion(
            sourceText: "Jeg lærer dansk",
            frame: CGRect(x: 40, y: 95, width: 180, height: 34),
            screenFrame: screen,
            displayID: 1,
            words: [word]
        )
        let focus = CGPoint(x: 125, y: 112)

        precondition(
            OCRRoutingPolicy.canUseAccurateFocusedVision(
                regions: [region],
                confidenceByRegionID: [region.id: 0.9],
                focusPoint: focus
            )
        )
        precondition(
            !OCRRoutingPolicy.canUseAccurateFocusedVision(
                regions: [region],
                confidenceByRegionID: [region.id: 0.2],
                focusPoint: focus
            )
        )
        precondition(
            !OCRRoutingPolicy.canUseAccurateFocusedVision(
                regions: [region],
                confidenceByRegionID: [region.id: 0.9],
                focusPoint: CGPoint(x: 400, y: 400)
            )
        )
        precondition(
            !OCRRoutingPolicy.canUseAccurateFocusedVision(
                regions: [region],
                confidenceByRegionID: [region.id: 0.9],
                focusPoint: nil
            )
        )

        let tinyWord = WordRegion(
            sourceText: "møblering",
            frame: CGRect(x: 100, y: 100, width: 55, height: 7),
            screenFrame: screen,
            displayID: 1
        )
        let tinyRegion = TextRegion(
            sourceText: "Månedlig leje inkl. evt. møblering",
            frame: tinyWord.frame,
            screenFrame: screen,
            displayID: 1,
            words: [tinyWord]
        )
        let tinyFocus = CGPoint(x: 125, y: 103)
        // Seven-point form text stays eligible; the gate exists to catch an
        // empty or unconfident reading, not a small one.
        precondition(
            OCRRoutingPolicy.canUseAccurateFocusedVision(
                regions: [tinyRegion],
                confidenceByRegionID: [tinyRegion.id: 0.8],
                focusPoint: tinyFocus
            )
        )
        precondition(
            !OCRRoutingPolicy.canUseAccurateFocusedVision(
                regions: [tinyRegion],
                confidenceByRegionID: [tinyRegion.id: 0.2],
                focusPoint: tinyFocus
            )
        )
        print("Confidence-routed OCR checks passed")
    }
}
