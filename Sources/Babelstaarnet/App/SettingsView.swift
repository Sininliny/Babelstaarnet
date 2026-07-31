import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Learning") {
                LabeledContent("Translation", value: "Danish → English")

                Picker(
                    "Explanation",
                    selection: $model.explanationMode
                ) {
                    ForEach(ExplanationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(
                    model.explanationMode == .english
                        ? "Show the English meaning and definition."
                        : "Show a short explanation written in simple Danish."
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
                        "Screen capture and OCR pause after 5 seconds without keyboard or pointer input, then resume automatically."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Local engines") {
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
        .frame(width: 480, height: 555)
    }
}
