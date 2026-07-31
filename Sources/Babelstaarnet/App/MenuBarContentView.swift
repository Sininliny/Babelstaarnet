import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            if model.screenPermissionGranted {
                learningControl

                HStack {
                    Text(model.explanationMode.menuTitle)
                    Spacer()
                    Text("fn  Z")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                if !model.openSourceEnginesReady {
                    Button("Install local engines") {
                        Task {
                            await model.installOpenSourceEngines()
                        }
                    }
                    .disabled(model.isInstallingEngines)
                }
            } else {
                permissionControl
            }

            Divider()

            HStack {
                Button("Open") {
                    openWindow(id: "main")
                }
                .buttonStyle(.plain)

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
            Image(
                systemName: statusIcon
            )
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
                            ? "Stop hover learning"
                            : "Start hover learning"
                    )
                    .font(.system(size: 12, weight: .semibold))

                    Text(
                        model.phase.isWorking
                            ? "Reading the screen…"
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

    private var statusIcon: String {
        if !model.learningModeActive {
            return "eye.slash"
        }
        return model.detectionSuspendedForIdle ? "eye" : "eye.fill"
    }

    private var statusText: String {
        if model.detectionSuspendedForIdle {
            return "Idle"
        }
        return model.learningModeActive ? "Active" : "Inactive"
    }

    private var permissionControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Screen Recording access is required.")
                .font(.system(size: 11, weight: .medium))
            Button(
                model.screenPermissionWasRequested
                    ? "Quit & Relaunch"
                    : "Allow access"
            ) {
                if model.screenPermissionWasRequested {
                    model.relaunch()
                } else {
                    model.requestScreenPermission()
                }
            }
            .buttonStyle(.bordered)
        }
    }
}
