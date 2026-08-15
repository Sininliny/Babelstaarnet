import SwiftUI
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
    }
}
