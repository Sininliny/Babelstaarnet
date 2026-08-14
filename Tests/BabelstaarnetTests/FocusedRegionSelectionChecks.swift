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
enum FocusedRegionSelectionChecks {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let first = region(
            text: "Jeg lærer dansk",
            word: "dansk",
            frame: CGRect(x: 80, y: 300, width: 70, height: 26),
            screen: screen
        )
        let second = region(
            text: "Hver eneste dag",
            word: "dag",
            frame: CGRect(x: 80, y: 240, width: 45, height: 26),
            screen: screen
        )

        let focused = FocusedRegionSelectionPolicy(language: .danish).foregroundRegions(
            from: [first, second],
            at: CGPoint(x: 110, y: 313)
        )
        precondition(focused == [first])
        precondition(
            FocusedRegionSelectionPolicy(language: .danish).focusedSourceKeys(
                in: [first, second],
                at: CGPoint(x: 110, y: 313)
            ) == ["dansk"]
        )

        // A line the sentence runs onto is kept with it. Dropping it here was
        // final: its words never reached translation, so the bubble could only
        // ever show the fragment the column happened to wrap.
        let opening = region(
            text: "Jeg lærer dansk, fordi jeg",
            word: "lærer",
            frame: CGRect(x: 80, y: 300, width: 180, height: 26),
            screen: screen
        )
        let continuation = region(
            text: "bor i landet.",
            word: "bor",
            frame: CGRect(x: 80, y: 274, width: 110, height: 26),
            screen: screen
        )
        precondition(
            FocusedRegionSelectionPolicy(language: .danish).foregroundRegions(
                from: [opening, continuation],
                at: CGPoint(x: 110, y: 313)
            ) == [opening, continuation]
        )

        let unfocused = FocusedRegionSelectionPolicy(language: .danish).foregroundRegions(
            from: [first, second],
            at: CGPoint(x: 500, y: 500)
        )
        precondition(unfocused == [first, second])
        precondition(
            FocusedRegionSelectionPolicy(language: .danish).focusedSourceKeys(
                in: [first, second],
                at: CGPoint(x: 500, y: 500)
            ).isEmpty
        )

        print("Focused foreground region checks passed")
    }

    private static func region(
        text: String,
        word: String,
        frame: CGRect,
        screen: CGRect
    ) -> TextRegion {
        TextRegion(
            sourceText: text,
            frame: frame,
            screenFrame: screen,
            displayID: 1,
            words: [
                WordRegion(
                    sourceText: word,
                    frame: frame,
                    screenFrame: screen,
                    displayID: 1
                )
            ]
        )
    }
}
