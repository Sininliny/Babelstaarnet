import AppKit
import CoreGraphics
import Foundation

enum OCRServiceCheckError: Error {
    case missingFixture
    case unreadableFixture
}

@main
struct OCRServiceCheck {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw OCRServiceCheckError.missingFixture
        }
        guard let image = NSImage(
            contentsOfFile: CommandLine.arguments[1]
        )?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRServiceCheckError.unreadableFixture
        }

        let displayID: CGDirectDisplayID = 42
        let screenFrame = CGRect(
            x: -1_400,
            y: 0,
            width: 1_400,
            height: 900
        )
        let captureFrame = CGRect(
            x: -1_260,
            y: 260,
            width: 700,
            height: 330
        )
        let capture = CapturedDisplay(
            displayID: displayID,
            image: image,
            frame: captureFrame,
            screenFrame: screenFrame
        )
        let startedAt = CFAbsoluteTimeGetCurrent()
        let result = try await OCRService().recognizeDanishText(in: capture)
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
        let source = result.regions.map(\.sourceText).joined(separator: " ")
        let words = result.regions.flatMap(\.words)

        precondition(source.contains("Godmorgen"))
        precondition(source.contains("lærer dansk"))
        precondition(source.contains("Hvid tekst på rød baggrund virker også"))
        precondition(source.contains("DANSKKURSER HOS A2B"))
        precondition(source.contains("Farvet dansk tekst"))
        precondition(source.contains("Månedlig leje"))
        precondition(source.contains("varmt vand"))
        precondition(source.contains("indflytningsmåned"))
        precondition(!source.localizedCaseInsensitiveContains("Finder"))
        precondition(!source.localizedCaseInsensitiveContains("Applications"))
        precondition(!words.isEmpty)
        precondition(words.allSatisfy { $0.displayID == displayID })
        precondition(words.allSatisfy { captureFrame.contains($0.frame) })
        precondition(words.allSatisfy { $0.screenFrame == screenFrame })
        precondition(elapsed < 2, "Cursor OCR exceeded 2 seconds: \(elapsed)")

        print(
            "Swift OCR service check passed: "
                + "\(words.count) Danish hover words via \(result.engine) "
                + "in \(elapsed.formatted(.number.precision(.fractionLength(3)))) s"
        )
    }
}
