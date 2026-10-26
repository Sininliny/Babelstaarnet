import AppKit
import Foundation
import SwiftUI
@testable import BabelstaarnetKit

@main @MainActor
enum EngineInstallerChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-install-checks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("install-local-engines.sh")
        let finished = directory.appendingPathComponent("finished")
        try """
        set -e
        if read -r answer; then exit 9; fi
        printf 'BABELSTAARNET_PROGRESS\\t1\\t9\\tFixture running\\n'
        sleep 0.3
        printf 'BABELSTAARNET_PROGRESS\\t4\\t9\\tPreparing dictionary\\n'
        printf 'dictionary loaded\\r'
        sleep 0.1
        touch finished
        printf 'BABELSTAARNET_PROGRESS\\t8\\t9\\tChecking engines\\n'
        """.write(to: script, atomically: true, encoding: .utf8)
        try "exit 0\n".write(
            to: directory.appendingPathComponent("install-contextual-glosses.sh"),
            atomically: true, encoding: .utf8
        )
        let service = EngineInstallerService(scriptDirectory: directory)
        var sawLiveProgress = false
        var blockedConcurrentInstall = false
        var latest: EngineInstallationProgress?
        _ = try await service.install { progress in
            latest = progress
            if progress.message == "Fixture running", !FileManager.default.fileExists(atPath: finished.path) {
                sawLiveProgress = true
            }
            if progress.message == "Fixture running" {
                do {
                    _ = try await service.installContextualGlosses()
                    preconditionFailure("Two installers modified one environment concurrently")
                } catch EngineInstallerError.installationInProgress {
                    blockedConcurrentInstall = true
                } catch {
                    preconditionFailure("Unexpected concurrent installer error: \(error)")
                }
            }
        }
        precondition(sawLiveProgress, "Progress arrived only after the installer ended")
        precondition(blockedConcurrentInstall)
        precondition(latest?.completedSteps == 8 && latest?.totalSteps == 9)

        // A failed installer must remain retryable, preserve the useful error,
        // and bound output even if a package manager prints a large log.
        try """
        for index in {1..400}; do printf '%0100d\\n' 0; done
        printf 'expected dictionary failure' >&2
        exit 17
        """.write(to: script, atomically: true, encoding: .utf8)
        do {
            _ = try await service.install()
            preconditionFailure("A failed installer was reported as successful")
        } catch EngineInstallerError.installationFailed(let message) {
            precondition(message.contains("expected dictionary failure"))
            precondition(message.utf8.count <= 16_384, "Installer logs grew without a bound")
        }
        try "printf 'repaired'\n".write(to: script, atomically: true, encoding: .utf8)
        let retried = try await service.install()
        precondition(retried == "repaired")

        precondition(EngineInstallationProgress(line: "BABELSTAARNET_PROGRESS\t10\t9\tInvalid") == nil)
        precondition(EngineInstallationProgress(line: "BABELSTAARNET_PROGRESS\t1\t0\tInvalid") == nil)
        precondition(EngineInstallationProgress(line: "ordinary package output") == nil)
        let stage = EngineInstallationProgress(line: "BABELSTAARNET_PROGRESS\t4\t9\tPreparing dictionary")!
        precondition(stage.fractionCompleted == 4.0 / 9.0)
        try renderProgress(stage)
        print("Engine installer live progress, failure, retry, serialization and native UI checks passed")
    }

    static func renderProgress(_ stage: EngineInstallationProgress) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            for (state, progress) in [("steps", stage), ("waiting", EngineInstallationProgress(message: "Installing language model"))] {
                let view = NSHostingView(rootView: EngineInstallationProgressView(progress: progress)
                    .padding(16).frame(width: 440)
                    .background(Color(nsColor: .windowBackgroundColor)))
                view.appearance = NSAppearance(named: appearance)
                let size = view.fittingSize
                precondition(size.width == 440 && size.height > 45 && size.height < 180)
                view.setFrameSize(size)
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    preconditionFailure("Installer progress could not render")
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(
                    to: output.appendingPathComponent("mac-engine-install-\(state)-\(name).png")
                )
            }
        }
    }
}
