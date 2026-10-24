import SwiftUI
import AppKit
import Translation

public struct TranslationHostView: View {
    @ObservedObject var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(model.translationConfiguration) { session in
                await model.translatePendingRegions(using: session)
            }
            .onChange(of: model.wordBookWindowRequest) { _, _ in
                openWindow(id: WordBookView.windowID); NSApp.activate(ignoringOtherApps: true)
            }
            .onChange(of: model.newsWindowRequest) { _, _ in
                openWindow(id: WordBookView.windowID); NSApp.activate(ignoringOtherApps: true)
            }
    }
    @Environment(\.openWindow) private var openWindow
}
