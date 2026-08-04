import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Learning") {
                LabeledContent(
                    "Learning translator",
                    value: "Danish-first"
                )

                Text(
                    "Familiar words stay Danish. New words receive only the English needed for understanding. Knew removes help for the focused word in one action; Don’t know immediately restores it. Spaced encounters quietly reduce support, while repeated hovering does not train the profile."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle(
                    "Word bridge",
                    isOn: Binding(
                        get: {
                            model.bridgeConfiguration.showsWordBridge
                        },
                        set: model.setWordBridgeEnabled
                    )
                )

                Toggle(
                    "Sentence bridge",
                    isOn: Binding(
                        get: {
                            model.bridgeConfiguration.showsSentenceBridge
                        },
                        set: model.setSentenceBridgeEnabled
                    )
                )

                Text(
                    "Use either bridge independently or show both together. Turning both off keeps Danish speech on hover."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle("Speak Danish on hover", isOn: $model.autoSpeak)

                HStack {
                    Text("Hover delay")
                    Slider(
                        value: $model.hoverDelay,
                        in: 0.2...1.2,
                        step: 0.05
                    )
                    Text(
                        model.hoverDelay.formatted(
                            .number.precision(.fractionLength(2))
                        ) + " s"
                    )
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
                }

                Toggle("Follow screen changes", isOn: $model.liveMode)
                    .disabled(!model.screenPermissionGranted)

                Toggle(
                    "Pause screen reading when idle",
                    isOn: $model.powerSavingEnabled
                )
                .disabled(!model.liveMode)

                if model.powerSavingEnabled {
                    Text(
                        "Screen capture and OCR back off while the pointer is still, stop while a bubble is held, and pause after 5 seconds without input."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Shortcuts") {
                ForEach(ConfigurableHotKeyAction.allCases) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorderView(
                            shortcut: model.hotKeyConfiguration.shortcut(
                                for: action
                            ),
                            onChange: { shortcut in
                                model.updateShortcut(
                                    shortcut,
                                    for: action
                                )
                            }
                        )
                        .frame(width: 128, height: 24)
                    }
                }

                Picker(
                    "Hold bubble",
                    selection: Binding(
                        get: {
                            model.hotKeyConfiguration.holdModifier
                        },
                        set: model.updateHoldModifier
                    )
                ) {
                    ForEach(BubbleHoldModifier.allCases) { modifier in
                        Text(modifier.title).tag(modifier)
                    }
                }

                Text(
                    "Click a shortcut, then press its replacement. Bubble shortcuts are active only while a learning bubble is visible."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let shortcutMessage = model.shortcutMessage {
                    Text(shortcutMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Restore Default Shortcuts") {
                    model.resetHotKeyConfiguration()
                }
            }

            Section("Learning data") {
                LabeledContent(
                    "Learning profile",
                    value: wordCountDescription(
                        model.learnerTrackedWordCount
                    )
                )
                LabeledContent(
                    "Probably understood",
                    value: wordCountDescription(
                        model.learnerFamiliarWordCount
                    )
                )

                Text(
                    "The profile controls where English appears in both bridges. It is stored only on this Mac; imports merge without double-counting."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Button("Export Profile") {
                        model.exportLearnerProfile()
                    }
                    .disabled(model.learnerTrackedWordCount == 0)

                    Button("Import Profile") {
                        model.importLearnerProfile()
                    }
                }

                if let learnerDataMessage = model.learnerDataMessage {
                    Text(learnerDataMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Reset learning profile", role: .destructive) {
                    model.confirmAndResetLearnerProfile()
                }
                .disabled(model.learnerTrackedWordCount == 0)
            }

            Section("Local engines") {
                Text(
                    "Optional: Babelstårnet can use Apple's built-in on-device engines without installing anything."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                LabeledContent("OCR", value: model.ocrEngineName)
                LabeledContent("Translation", value: model.translationEngineName)
                LabeledContent(
                    "Adaptive word bridge",
                    value: model.wordBridgeEngineReady
                        ? "Local explanations ready"
                        : "Local resources not installed"
                )
                Button(
                    model.openSourceEnginesReady
                        ? "Check engines"
                        : "Install engines"
                ) {
                    Task {
                        if model.openSourceEnginesReady {
                            await model.checkEngineReadiness()
                        } else {
                            await model.installOpenSourceEngines()
                        }
                    }
                }
                .disabled(model.isInstallingEngines)
            }

            Section("Access") {
                LabeledContent(
                    "Screen Recording",
                    value: model.screenPermissionGranted ? "Allowed" : "Required"
                )

                Button("Open Screen Recording Settings") {
                    model.openScreenRecordingSettings()
                }

                Text("Screenshots, recognized text, translation, definitions, and speech remain on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(
            width: 480,
            height: 760
        )
    }

    private func wordCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "word" : "words")"
    }
}
