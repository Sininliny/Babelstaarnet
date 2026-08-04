import SwiftUI

@main
struct BabelstaarnetApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            Image(nsImage: menuBarIcon)
                .accessibilityLabel(menuBarTitle)
                .background {
                    TranslationHostView(model: model)
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }

    private var menuBarIcon: NSImage {
        model.learningModeActive
            ? BabelstaarnetIcon.activeMenuBarImage
            : BabelstaarnetIcon.inactiveMenuBarImage
    }

    private var menuBarTitle: String {
        if !model.learningModeActive {
            return "Babelstårnet — detection inactive"
        }
        return model.detectionSuspendedForIdle
            ? "Babelstårnet — detection paused while idle"
            : "Babelstårnet — detection active"
    }
}
