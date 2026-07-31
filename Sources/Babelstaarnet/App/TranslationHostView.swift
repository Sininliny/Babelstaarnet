import SwiftUI
import Translation

struct TranslationHostView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(model.translationConfiguration) { session in
                await model.translatePendingRegions(using: session)
            }
    }
}
