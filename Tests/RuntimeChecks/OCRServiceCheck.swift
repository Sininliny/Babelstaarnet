import AppKit
import CoreGraphics
import Foundation
@testable import BabelstaarnetKit

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
        let service = OCRService()
        // The app warms the recognizer at activation; the first accurate
        // request in a process otherwise pays a one-time model load that has
        // been observed to take tens of seconds.
        await service.warmUp()

        let focusPoint = CGPoint(x: -1_190, y: 420)
        let focusedStartedAt = CFAbsoluteTimeGetCurrent()
        let focusedResult = try await service.recognizeDanishText(
            in: capture,
            focusPoint: focusPoint
        )
        let focusedElapsed = CFAbsoluteTimeGetCurrent() - focusedStartedAt
        let focusedSource = focusedResult.regions
            .map(\.sourceText)
            .joined(separator: " ")
        precondition(
            focusedResult.engine.hasPrefix("Apple Vision"),
            "Focused OCR did not stay on the Vision path: "
                + focusedResult.engine
        )
        precondition(focusedSource.contains("Godmorgen"))
        precondition(
            focusedElapsed < 0.5,
            "Focused OCR exceeded 500 ms: \(focusedElapsed)"
        )

        // Danish diacritics are the whole point of reading the source language.
        // A dropped ring or slash is not a smaller error; it changes which word
        // gets translated, so the focused pass has to preserve them exactly.
        let diacriticFocus = CGPoint(x: -1_100, y: 552)
        let diacriticResult = try await OCRService().recognizeDanishText(
            in: capture,
            focusPoint: diacriticFocus
        )
        let diacriticWords = diacriticResult.regions.flatMap(\.words)
        for expected in ["på", "rød", "også"] {
            precondition(
                diacriticWords.contains { $0.sourceText == expected },
                "Focused OCR lost the diacritic in “\(expected)”: "
                    + diacriticWords.map(\.sourceText).joined(separator: " ")
            )
        }

        let startedAt = CFAbsoluteTimeGetCurrent()
        let result = try await service.recognizeDanishText(in: capture)
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
        let source = result.regions.map(\.sourceText).joined(separator: " ")
        let words = result.regions.flatMap(\.words)

        precondition(source.contains("Godmorgen"))
        precondition(source.contains("lærer dansk"))
        precondition(source.contains("Hvid tekst på rød baggrund virker også"))
        precondition(source.contains("DANSKKURSER HOS A2B"))
        precondition(source.contains("IKEA Family medlemspris"))
        precondition(
            source.contains("Månedlig leje"),
            "OCR missed 10-point rent text: \(source)"
        )
        precondition(
            source.contains("varmt vand"),
            "OCR missed 10-point heating text: \(source)"
        )
        precondition(
            source.contains("indflytningsmåned"),
            "OCR missed 10-point move-in text: \(source)"
        )
        precondition(!source.localizedCaseInsensitiveContains("Finder"))
        precondition(!source.localizedCaseInsensitiveContains("Applications"))
        precondition(!words.isEmpty)
        precondition(words.allSatisfy { $0.displayID == displayID })
        precondition(words.allSatisfy { captureFrame.contains($0.frame) })
        precondition(words.allSatisfy { $0.screenFrame == screenFrame })
        precondition(elapsed < 2.2, "Full OCR exceeded 2.2 seconds: \(elapsed)")

        guard let tinyWord = words.first(where: {
            $0.sourceText.localizedCaseInsensitiveContains("møblering")
        }) else {
            preconditionFailure("Tiny-text fixture word was not recognized.")
        }
        let tinyService = OCRService()
        let tinyStartedAt = CFAbsoluteTimeGetCurrent()
        let tinyResult = try await tinyService.recognizeDanishText(
            in: capture,
            focusPoint: CGPoint(x: tinyWord.frame.midX, y: tinyWord.frame.midY)
        )
        let tinyElapsed = CFAbsoluteTimeGetCurrent() - tinyStartedAt
        let tinySource = tinyResult.regions
            .map(\.sourceText)
            .joined(separator: " ")
        precondition(tinySource.localizedCaseInsensitiveContains("møblering"))
        precondition(
            tinyResult.engine.hasPrefix("Apple Vision")
                || tinyResult.engine == "Tesseract OCR",
            "Unexpected tiny-text engine: \(tinyResult.engine)"
        )
        precondition(
            tinyElapsed < 1.8,
            "Focused tiny-text OCR via \(tinyResult.engine) exceeded 1.8 seconds: \(tinyElapsed); \(tinySource)"
        )

        let cacheStartedAt = CFAbsoluteTimeGetCurrent()
        let cached = try await service.recognizeDanishText(in: capture)
        let cacheElapsed = CFAbsoluteTimeGetCurrent() - cacheStartedAt
        precondition(cached.regions == result.regions)
        precondition(
            cacheElapsed < 0.05,
            "Unchanged OCR cache exceeded 50 ms: \(cacheElapsed)"
        )

        let blueFocusPoint = CGPoint(x: -1_180, y: 478)
        let blueStartedAt = CFAbsoluteTimeGetCurrent()
        let blueResult = try await service.recognizeDanishText(
            in: capture,
            focusPoint: blueFocusPoint
        )
        let blueElapsed = CFAbsoluteTimeGetCurrent() - blueStartedAt
        let blueSource = blueResult.regions
            .map(\.sourceText)
            .joined(separator: " ")
        precondition(blueSource.contains("rabat"))
        precondition(
            blueResult.regions.flatMap(\.words).contains {
                $0.sourceText.localizedCaseInsensitiveContains("rabat")
                    && $0.frame
                        .insetBy(dx: -4, dy: -5)
                        .contains(blueFocusPoint)
            }
        )
        precondition(
            blueElapsed < 2.3,
            "Blue focused OCR exceeded 2.3 seconds: \(blueElapsed)"
        )

        let cancellationService = OCRService()
        let cancellationTask = Task {
            try await cancellationService.recognizeDanishText(in: capture)
        }
        try await Task.sleep(for: .milliseconds(50))
        let cancellationStartedAt = CFAbsoluteTimeGetCurrent()
        cancellationTask.cancel()
        do {
            _ = try await cancellationTask.value
            preconditionFailure("Cancelled OCR unexpectedly returned a result.")
        } catch is CancellationError {
        }
        let cancellationElapsed = CFAbsoluteTimeGetCurrent()
            - cancellationStartedAt
        precondition(
            cancellationElapsed < 0.7,
            "Cancelled OCR took too long to stop: \(cancellationElapsed)"
        )

        print(
            "Swift OCR service check passed: focused \(focusedResult.engine) in "
                + "\(focusedElapsed.formatted(.number.precision(.fractionLength(3)))) s; "
                + "blue text via \(blueResult.engine) in "
                + "\(blueElapsed.formatted(.number.precision(.fractionLength(3)))) s; "
                + "full \(words.count) words via \(result.engine) in "
                + "\(elapsed.formatted(.number.precision(.fractionLength(3)))) s; "
                + "tiny text via \(tinyResult.engine) in "
                + "\(tinyElapsed.formatted(.number.precision(.fractionLength(3)))) s; "
                + "unchanged cache in "
                + "\(cacheElapsed.formatted(.number.precision(.fractionLength(3)))) s"
        )
    }
}
