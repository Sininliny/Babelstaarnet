import Foundation
@testable import BabelTranslate
@testable import LanguageDanish

@main
enum ArgosWorkerStartupChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArgosWorkerChecks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        func worker(_ name: String, prelude: String, timeout: TimeInterval = 2)
            throws -> ArgosTranslationService {
            let script = directory.appendingPathComponent("\(name).py")
            try """
            import json, pathlib, sys, time
            \(prelude)
            for line in sys.stdin:
                request = json.loads(line)
                texts = request.get("texts", request.get("define_words", []))
                print(json.dumps({"translations": ["translated:" + text for text in texts]}), flush=True)
            """.write(to: script, atomically: true, encoding: .utf8)
            return ArgosTranslationService(
                languages: .danishToEnglish,
                pythonPath: "/usr/bin/python3",
                bridgeURL: script,
                responseTimeout: timeout
            )
        }

        // More than a pipe can hold, before the worker reads its first request.
        let noisy = try worker(
            "noisy",
            prelude: "sys.stderr.buffer.write(b'warning\\n' * 32768); sys.stderr.flush()"
        )
        let noisyReady = await noisy.isReady()
        precondition(noisyReady, "Startup warnings blocked the readiness check")
        let translated = try await noisy.translate(["hej", "ordbog"])
        precondition(translated == ["translated:hej", "translated:ordbog"])
        let wordBridgeReady = await noisy.isWordBridgeReady()
        precondition(wordBridgeReady, "Word-bridge readiness failed after startup warnings")
        await noisy.shutdown()

        for (name, prelude) in [
            ("silent", "time.sleep(30)"),
            ("partial", "sys.stdout.write('{'); sys.stdout.flush(); time.sleep(30)"),
            ("trickle", """
            for _ in range(30):
                sys.stdout.write(' ')
                sys.stdout.flush()
                time.sleep(0.1)
            """),
        ] {
            let stalled = try worker(name, prelude: prelude, timeout: 0.2)
            let started = ContinuousClock.now
            let ready = await stalled.isReady()
            precondition(!ready, "An unresponsive worker reported ready")
            precondition(
                started.duration(to: .now) >= .milliseconds(150),
                "The stalled fixture exited before the deadline was tested"
            )
            precondition(
                started.duration(to: .now) < .seconds(2),
                "The readiness check did not stop at its deadline"
            )
            await stalled.shutdown()
        }

        // Closing stdout while keeping stderr open must also return promptly.
        let closedOutput = try worker(
            "closed-output",
            prelude: "import os; os.close(1); time.sleep(30)"
        )
        let closedStarted = ContinuousClock.now
        let closedReady = await closedOutput.isWordBridgeReady()
        precondition(!closedReady, "A worker with closed output reported ready")
        precondition(closedStarted.duration(to: .now) < .seconds(1))
        await closedOutput.shutdown()

        let cancellable = try worker("cancelled", prelude: "time.sleep(30)")
        let cancelledStarted = ContinuousClock.now
        let readiness = Task { await cancellable.isReady() }
        try await Task.sleep(for: .milliseconds(100))
        readiness.cancel()
        let cancelledReady = await readiness.value
        precondition(!cancelledReady, "A cancelled readiness check reported ready")
        precondition(cancelledStarted.duration(to: .now) < .seconds(1))
        await cancellable.shutdown()

        let marker = directory.appendingPathComponent("first-start").path
        let recovery = try worker(
            "recovery",
            prelude: """
            marker = pathlib.Path(\(String(reflecting: marker)))
            if not marker.exists():
                marker.touch()
                time.sleep(30)
            """,
            timeout: 0.2
        )
        let recovered = try await recovery.translate(["hej"])
        precondition(recovered == ["translated:hej"], "The stalled worker was not replaced")
        await recovery.shutdown()
        print("Argos worker startup, deadline, and recovery checks passed")
    }
}
