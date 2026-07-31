import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.vertical, 18)

            Divider()

            VStack(spacing: 18) {
                languageRow

                if model.screenPermissionGranted {
                    learningControl

                    if !model.openSourceEnginesReady {
                        engineNotice
                    }
                } else {
                    permissionNotice
                }
            }
            .padding(22)
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            footer
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
        }
        .frame(width: 500, height: windowHeight)
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Babelstårnet")
                    .font(.system(size: 18, weight: .semibold))
                Text("Danish, wherever you read")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            status
        }
    }

    private var status: some View {
        HStack(spacing: 6) {
            if model.phase.isWorking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(
                        model.detectionSuspendedForIdle
                            ? Color.secondary.opacity(0.55)
                            : model.learningModeActive
                                ? Color.primary
                                : Color.secondary.opacity(0.45)
                    )
                    .frame(width: 6, height: 6)
            }

            Text(statusText)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var statusText: String {
        if model.phase.isWorking {
            return "Reading…"
        }
        if case .failed = model.phase {
            return "Needs attention"
        }
        if model.detectionSuspendedForIdle {
            return "Idle · paused"
        }
        return model.learningModeActive ? "Active" : "Inactive"
    }

    private var windowHeight: CGFloat {
        if !model.screenPermissionGranted {
            return 320
        }
        return model.openSourceEnginesReady ? 285 : 340
    }

    private var languageRow: some View {
        HStack(spacing: 10) {
            Text("Danish")
                .fontWeight(.medium)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(
                model.explanationMode == .english
                    ? "English"
                    : "Easy Danish"
            )
                .fontWeight(.medium)
            Spacer()
            Text("Local")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 12))
    }

    private var learningControl: some View {
        Button {
            Task {
                await model.toggleLearningMode()
            }
        } label: {
            HStack(spacing: 13) {
                Image(
                    systemName: model.learningModeActive
                        ? "pause.fill"
                        : "cursorarrow.motionlines"
                )
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        model.learningModeActive
                            ? "Stop hover learning"
                            : "Start hover learning"
                    )
                    .font(.system(size: 14, weight: .semibold))

                    Text(
                        model.learningModeActive
                            ? model.detectionSuspendedForIdle
                                ? "Move the pointer to resume"
                                : "Move over a Danish word to learn it"
                            : "Works with text and images"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                shortcutKey
            }
            .foregroundStyle(.primary)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                model.learningModeActive
                    ? Color.primary.opacity(0.075)
                    : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.primary.opacity(0.12), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.phase.isWorking && !model.learningModeActive)
    }

    private var shortcutKey: some View {
        Text("fn  Z")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.primary.opacity(0.11), lineWidth: 0.7)
            }
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "Allow Screen Recording to read words under the pointer.",
                systemImage: "rectangle.on.rectangle.slash"
            )
            .font(.system(size: 12, weight: .medium))

            HStack {
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

                Button("System Settings") {
                    model.openScreenRecordingSettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var engineNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
            Text(model.engineSetupMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button(model.isInstallingEngines ? "Installing…" : "Install") {
                Task {
                    await model.installOpenSourceEngines()
                }
            }
            .disabled(model.isInstallingEngines)
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            Label("On-device only", systemImage: "lock")
                .foregroundStyle(.tertiary)
            Spacer()
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 10))
    }
}
