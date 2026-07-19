import SwiftUI

@main
struct ScreenshotApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("ScreenshotApp Bogdan", systemImage: "camera.viewfinder") {
            MenuBarView(model: appDelegate.model)
        }

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}
