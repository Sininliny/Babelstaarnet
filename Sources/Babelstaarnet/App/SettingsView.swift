import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Learning") {
                Picker(
                    "Translate",
                    selection: $model.translationMode
                ) {
                    ForEach(TranslationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Picker(
                    "Explain",
                    selection: $model.explanationMode
                ) {
                    ForEach(ExplanationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text(configurationHelp)
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
                    "The profile controls which words stay Danish in mixed explanations. It is stored only on this Mac; imports merge without double-counting."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Button("Export Profile…") {
                        model.exportLearnerProfile()
                    }
                    .disabled(model.learnerTrackedWordCount == 0)

                    Button("Import Profile…") {
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
                    "Easy Danish",
                    value: model.wordWiseEngineReady
                        ? "Local definitions — ready"
                        : "Model required"
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
            height: 680
        )
    }

    private var configurationHelp: String {
        let translation = model.translationMode == .english
            ? "Show the English translation."
            : "Hide the translation."
        let explanation: String
        switch model.explanationMode {
        case .adaptive:
            explanation = "Mix Danish with English according to your local learning profile."
        case .beginner:
            explanation = "Use a short beginner-friendly English gloss."
        case .easyDanish:
            explanation = "Explain the word in simple Danish."
        case .english:
            explanation = "Show the fuller English dictionary definition."
        case .none:
            explanation = "Hide the explanation."
        }
        return "\(translation) \(explanation)"
    }

    private func wordCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "word" : "words")"
    }
}
