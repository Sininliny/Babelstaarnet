import SwiftUI

@main
struct BabelstaarnetApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Both local engines are talked to over a pipe, and a pipe whose reader
        // has gone kills the writer outright unless this is said: the default
        // disposition for SIGPIPE is to terminate, and an AppKit process does
        // not change it. Tesseract exiting before it has read the capture —
        // which is exactly what an install without dan.traineddata does, on
        // every scan — then took the whole app down instead of falling back to
        // Vision. Ignored, the write fails as an ordinary error the caller can
        // handle.
        signal(SIGPIPE, SIG_IGN)
    }

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
