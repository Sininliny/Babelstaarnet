import CoreGraphics
import Foundation

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

        let focused = FocusedRegionSelectionPolicy.foregroundRegions(
            from: [first, second],
            at: CGPoint(x: 110, y: 313)
        )
        precondition(focused == [first])

        let unfocused = FocusedRegionSelectionPolicy.foregroundRegions(
            from: [first, second],
            at: CGPoint(x: 500, y: 500)
        )
        precondition(unfocused == [first, second])

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
