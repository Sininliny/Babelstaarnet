import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Translation") {
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

                Text(
                    "Hovering a Danish word shows what it means. Use either panel on its own or both together; turning both off keeps Danish speech on hover."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle("Speak Danish on hover", isOn: $model.autoSpeak)

                // This slider only ever delayed the pronunciation. Under its
                // old name, in its own section, it read as a delay on the
                // bubble — which appears as soon as the word is recognized and
                // is not waited on at all.
                HStack {
                    Text("Speak after")
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
                .disabled(!model.autoSpeak)

                Text(
                    "How long the pointer rests on a word before it is spoken. The bubble itself appears as soon as the word is read."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Reading") {
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

            Section("What you have picked up") {
                LabeledContent(
                    "Danish words seen",
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
                    "Babelstårnet keeps track of which Danish words keep coming back to you and quietly shows less English for those. Nothing here needs your attention — reading is enough to move it. Knew and Don’t know are there for the times it gets a word wrong. Stored only on this Mac; imports merge without double-counting."
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

                Button("Reset what Babelstårnet has learned", role: .destructive) {
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
        // A fixed 760-point height does not fit under the menu bar on a 13"
        // display at its default scaling, which put the last section — the one
        // holding screen access — off the bottom of the window with no way to
        // reach it. The form scrolls, so it only needs a floor.
        .frame(width: 480)
        .frame(
            minHeight: 420,
            idealHeight: 760,
            maxHeight: .infinity
        )
    }

    private func wordCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "word" : "words")"
    }
}
