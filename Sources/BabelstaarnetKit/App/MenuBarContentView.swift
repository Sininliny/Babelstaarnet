import AppKit
import SwiftUI
import BabelCore
import BabelLexicon
import BabelOCR
import BabelSpeech
import BabelTranslate
import LanguageDanish

public struct MenuBarContentView: View {
    @ObservedObject var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            if model.screenPermissionGranted {
                learningControl

                if let failureMessage = model.failureMessage {
                    failureNotice(failureMessage)
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hover to translate")
                        Text("Danish stays · English fills the gaps")
                    }
                    Spacer()
                    Text(model.toggleLearningShortcutLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    Toggle(
                        "Word meaning",
                        isOn: Binding(
                            get: {
                                model.bridgeConfiguration.showsWordBridge
                            },
                            set: model.setWordBridgeEnabled
                        )
                    )
                    Toggle(
                        "Whole sentence",
                        isOn: Binding(
                            get: {
                                model.bridgeConfiguration.showsSentenceBridge
                            },
                            set: model.setSentenceBridgeEnabled
                        )
                    )
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

                bubbleShortcutHint

            } else {
                permissionControl
            }

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings")
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
        }
        .padding(14)
        .frame(width: 290)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(nsImage: statusIcon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 26, height: 26)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))

            Text("Babelstårnet")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            if model.phase.isWorking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Why reading stopped on its own, shown where the reader comes to start it
    /// again. Without this the app just went quiet: hovering stopped answering
    /// and nothing anywhere said what had gone wrong.
    private func failureNotice(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Retry") {
                Task {
                    await model.toggleLearningMode()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tint)
        }
        .padding(9)
        .background(
            .orange.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .accessibilityElement(children: .combine)
    }

    /// The bubble itself stays out of the way while reading, so the shortcuts
    /// it responds to are discoverable here instead of on every hover.
    private var bubbleShortcutHint: some View {
        HStack(spacing: 5) {
            ForEach(model.bubbleShortcutHints, id: \.label) { hint in
                Text(hint.key)
                    .font(
                        .system(size: 9, weight: .semibold, design: .rounded)
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        .quaternary.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                Text(hint.label)
                    .font(.system(size: 10))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }

    private var learningControl: some View {
        Button {
            Task {
                await model.toggleLearningMode()
            }
        } label: {
            HStack(spacing: 10) {
                Image(
                    systemName: model.learningModeActive
                        ? "pause.fill"
                        : "cursorarrow.motionlines"
                )
                .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        model.learningModeActive
                            ? "Stop translating"
                            : "Start translating"
                    )
                    .font(.system(size: 12, weight: .semibold))

                    Text(
                        model.phase.isWorking
                            ? "Reading the screen"
                            : model.detectionSuspendedForIdle
                                ? "Paused until your next input"
                                : "Hover any Danish word"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var statusIcon: NSImage {
        model.learningModeActive
            ? BabelstaarnetIcon.activeMenuBarImage
            : BabelstaarnetIcon.inactiveMenuBarImage
    }

    private var statusText: String {
        if model.detectionSuspendedForIdle {
            return "Idle"
        }
        return model.learningModeActive ? "Active" : "Inactive"
    }

    private var permissionControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Complete the one-time screen access setup.")
                .font(.system(size: 11, weight: .medium))
            Button(
                model.screenPermissionWasRequested
                    ? "Open System Settings"
                    : "Set up Babelstårnet"
            ) {
                if model.screenPermissionWasRequested {
                    model.openScreenRecordingSettings()
                } else {
                    model.beginGuidedSetup()
                }
            }
            .buttonStyle(.bordered)

            if model.screenPermissionWasRequested {
                Button("Enabled it? Relaunch") {
                    model.relaunch()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}
