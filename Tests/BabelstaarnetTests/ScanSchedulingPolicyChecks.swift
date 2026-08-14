import CoreGraphics
import Foundation
@testable import BabelstaarnetKit

@main
enum ScanSchedulingPolicyChecks {
    static func main() {
        precondition(
            !ScanSchedulingPolicy.shouldReplaceActiveScan(
                origin: .zero,
                current: CGPoint(x: 18, y: 0),
                estimatedTextHeight: 20
            )
        )
        precondition(
            ScanSchedulingPolicy.shouldReplaceActiveScan(
                origin: .zero,
                current: CGPoint(x: 32, y: 0),
                estimatedTextHeight: 20
            )
        )

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

        precondition(
            ScanSchedulingPolicy.canReuseRecognizedWord(
                at: CGPoint(x: 125, y: 112),
                in: [region],
                resultAge: 0.4,
                refreshInterval: 1.5
            )
        )
        precondition(
            !ScanSchedulingPolicy.canReuseRecognizedWord(
                at: CGPoint(x: 300, y: 300),
                in: [region],
                resultAge: 0.4,
                refreshInterval: 1.5
            )
        )
        precondition(
            !ScanSchedulingPolicy.canReuseRecognizedWord(
                at: CGPoint(x: 125, y: 112),
                in: [region],
                resultAge: 1.5,
                refreshInterval: 1.5
            )
        )

        print("Latest-cursor scan scheduling checks passed")
    }
}
