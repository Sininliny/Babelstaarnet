import SwiftUI

@main
struct BabelstaarnetApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Babelstårnet", id: "main") {
            MainWindowView(model: model)
        }
        .defaultSize(width: 500, height: 400)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            Label(menuBarTitle, systemImage: menuBarIcon)
                .background {
                    TranslationHostView(model: model)
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }

    private var menuBarIcon: String {
        if !model.learningModeActive {
            return "eye.slash"
        }
        return model.detectionSuspendedForIdle ? "eye" : "eye.fill"
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
