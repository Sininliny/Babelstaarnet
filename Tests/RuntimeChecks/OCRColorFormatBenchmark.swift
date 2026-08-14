import AppKit
import CoreGraphics
import Foundation
@testable import BabelCore
@testable import BabelOCR
@testable import BabelTranslate
@testable import BabelLexicon
@testable import BabelSpeech
@testable import LanguageDanish
@testable import BabelstaarnetKit

/// Measures OCR accuracy across colour and format variations.
///
/// The app only ever shows a learner the word under the pointer, so the
/// benchmark weighs two different things: whether the pointer word was located
/// with usable bounds (`focus`), and whether the surrounding sentence was
/// recovered well enough to build a sentence bridge (`recall`).
///
/// Pass `--baseline <path>` to compare against a previous run and
/// `--record <path>` to store the current run.
@main
struct OCRColorFormatBenchmark {
    private struct Measurement {
        let scenario: OCRScenario
        let focusHit: Bool
        let recall: Double
        let engine: String
        let elapsed: Double
    }

    static func main() async throws {
        let arguments = CommandLine.arguments
        let baselinePath = value(for: "--baseline", in: arguments)
        let recordPath = value(for: "--record", in: arguments)
        let minimumScore = value(for: "--minimum-score", in: arguments)
            .flatMap(Double.init)

        let scenarios = try OCRScenarioFactory.allScenarios()
        // The first accurate Vision request in a process pays a one-time model
        // load. Pay it here, as the app does at activation, so the numbers
        // below describe recognition rather than start-up.
        let warmUpStartedAt = CFAbsoluteTimeGetCurrent()
        await OCRService(language: .danish).warmUp()
        print(
            "warm-up \(Int((CFAbsoluteTimeGetCurrent() - warmUpStartedAt) * 1_000)) ms\n"
        )

        var measurements: [Measurement] = []
        for scenario in scenarios {
            measurements.append(try await measure(scenario))
        }

        report(measurements)
        let score = overallScore(measurements)

        if let baselinePath,
           let baseline = loadScores(at: baselinePath) {
            compare(measurements, against: baseline)
        }
        if let recordPath {
            try saveScores(measurements, to: recordPath)
            print("Recorded scores to \(recordPath)")
        }
        if let minimumScore {
            precondition(
                score >= minimumScore,
                "OCR colour and format score \(formatted(score)) fell below "
                    + "the required \(formatted(minimumScore))."
            )
        }
    }

    private static func measure(
        _ scenario: OCRScenario
    ) async throws -> Measurement {
        // A fresh service per scenario keeps the bounded result cache from
        // masking a slow pass behind an earlier scenario's hit.
        let service = OCRService(language: .danish)
        let startedAt = CFAbsoluteTimeGetCurrent()
        let result = try await service.recognizeText(
            in: scenario.capture,
            focusPoint: scenario.focusPoint
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt

        let words = result.regions.flatMap(\.words)
        let focusHit = words.contains { word in
            normalized(word.sourceText) == normalized(scenario.focusWord)
                && word.frame
                    .insetBy(dx: -4, dy: -5)
                    .contains(scenario.focusPoint)
        }
        let recognized = Set(
            words.map { normalized($0.sourceText) }.filter { !$0.isEmpty }
        )
        let found = scenario.expectedWords.filter {
            recognized.contains(normalized($0))
        }
        let recall = scenario.expectedWords.isEmpty
            ? 1
            : Double(found.count) / Double(scenario.expectedWords.count)

        return Measurement(
            scenario: scenario,
            focusHit: focusHit,
            recall: recall,
            engine: result.engine,
            elapsed: elapsed
        )
    }

    /// The pointer word is the product; sentence recall is supporting context.
    private static func score(_ measurement: Measurement) -> Double {
        (measurement.focusHit ? 0.6 : 0) + measurement.recall * 0.4
    }

    private static func overallScore(_ measurements: [Measurement]) -> Double {
        guard !measurements.isEmpty else {
            return 0
        }
        return measurements.map(score).reduce(0, +)
            / Double(measurements.count)
    }

    private static func report(_ measurements: [Measurement]) {
        print(
            pad("scenario", 22)
                + pad("axis", 12)
                + pad("focus", 7)
                + pad("recall", 8)
                + pad("score", 8)
                + pad("ms", 7)
                + "engine"
        )
        print(String(repeating: "-", count: 92))
        for measurement in measurements {
            print(
                pad(measurement.scenario.name, 22)
                    + pad(measurement.scenario.axis.rawValue, 12)
                    + pad(measurement.focusHit ? "hit" : "MISS", 7)
                    + pad(formatted(measurement.recall), 8)
                    + pad(formatted(score(measurement)), 8)
                    + pad(
                        String(Int((measurement.elapsed * 1_000).rounded())),
                        7
                    )
                    + measurement.engine
            )
        }
        print(String(repeating: "-", count: 92))

        let byAxis = Dictionary(
            grouping: measurements,
            by: \.scenario.axis
        )
        for axis in byAxis.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            let group = byAxis[axis] ?? []
            print(
                pad(axis.rawValue, 22)
                    + "score "
                    + formatted(overallScore(group))
                    + "  focus "
                    + "\(group.filter(\.focusHit).count)/\(group.count)"
            )
        }
        let focusHits = measurements.filter(\.focusHit).count
        let slowest = measurements.map(\.elapsed).max() ?? 0
        print(
            "\noverall score \(formatted(overallScore(measurements)))"
                + "  focus \(focusHits)/\(measurements.count)"
                + "  slowest \(Int((slowest * 1_000).rounded())) ms"
        )
    }

    private static func compare(
        _ measurements: [Measurement],
        against baseline: [String: Double]
    ) {
        print("\nchange against baseline")
        var regressed: [String] = []
        for measurement in measurements {
            guard let previous = baseline[measurement.scenario.name] else {
                print(pad(measurement.scenario.name, 22) + "new")
                continue
            }
            let delta = score(measurement) - previous
            guard abs(delta) >= 0.005 else {
                continue
            }
            print(
                pad(measurement.scenario.name, 22)
                    + (delta > 0 ? "+" : "")
                    + formatted(delta)
                    + "  (\(formatted(previous)) → "
                    + "\(formatted(score(measurement))))"
            )
            if delta < 0 {
                regressed.append(measurement.scenario.name)
            }
        }
        if regressed.isEmpty {
            print("no scenario regressed")
        } else {
            print("regressed: \(regressed.joined(separator: ", "))")
        }
    }

    private static func loadScores(at path: String) -> [String: Double]? {
        guard let data = FileManager.default.contents(atPath: path),
              let scores = try? JSONDecoder().decode(
                  [String: Double].self,
                  from: data
              ) else {
            return nil
        }
        return scores
    }

    private static func saveScores(
        _ measurements: [Measurement],
        to path: String
    ) throws {
        let scores = Dictionary(
            uniqueKeysWithValues: measurements.map {
                ($0.scenario.name, score($0))
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(scores).write(
            to: URL(fileURLWithPath: path),
            options: .atomic
        )
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines
                    .union(.punctuationCharacters)
            )
            .lowercased()
    }

    private static func value(
        for flag: String,
        in arguments: [String]
    ) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func pad(_ value: String, _ width: Int) -> String {
        value.count >= width
            ? value + " "
            : value + String(repeating: " ", count: width - value.count)
    }
}
