import SwiftUI
import AppKit
import BabelCore

struct LanguagePackagesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var packages: LanguagePackageManager
    var body: some View {
        Picker("I am learning", selection: $packages.source) {
            ForEach(LanguageCatalog.languages) { Text($0.displayName).tag($0.id) }
        }
        Picker("Help me in", selection: $packages.target) {
            ForEach(LanguageCatalog.languages) { Text($0.displayName).tag($0.id) }
        }
        HStack {
            Button("Swap") { (packages.source, packages.target) = (packages.target, packages.source) }
            Button("Apply & restart") { model.applyLanguages() }.disabled(!packages.valid || !packages.changed)
        }.disabled(packages.busy)
        Text(packages.valid ? packages.route : "Choose two different languages.").font(.caption).foregroundStyle(.secondary)
        Text("Switching keeps each direction’s Word Book and learning records. Your existing Danish → English data stays in place.").font(.caption).foregroundStyle(.secondary)
        ForEach(LanguageCatalog.modelEdges(source: packages.source, target: packages.target), id: \.self) { edge in
            LabeledContent(edge, value: packages.state.models.contains(edge) ? "Installed" : "Missing")
        }
        if LanguageCatalog.language(packages.source).cjk || LanguageCatalog.language(packages.target).cjk {
            LabeledContent("Chinese script conversion", value: packages.state.conversion ? "Installed" : "Missing")
        }
        HStack {
            Button("Install translation · internet") { Task { await model.manageLanguagePackages("install") } }
            Button("Refresh") { Task { await model.manageLanguagePackages("status") } }
        }.disabled(packages.busy || !packages.valid)
        Button("Remove direction", role: .destructive) { Task { await model.manageLanguagePackages("remove") } }
            .disabled(packages.busy || !packages.state.installed.contains(packages.pairID))
        Text("Removing a direction preserves models required by other installed directions, existing models and learning data.").font(.caption).foregroundStyle(.secondary)
        LabeledContent("Source OCR", value: "Apple Vision · built in")
        LabeledContent("Speech", value: model.speechVoice?.name ?? "Install a matching offline voice in macOS")
        Button("Manage macOS voices") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent") { NSWorkspace.shared.open(url) }
        }
        if packages.busy { ProgressView().controlSize(.small) }
        Text(packages.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            .task { await packages.manage("status") }
    }
}
