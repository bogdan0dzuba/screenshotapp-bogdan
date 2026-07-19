import SwiftUI

@main
struct ScreenshotApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(AppIdentity.displayName, systemImage: "camera.viewfinder") {
            MenuBarView(model: appDelegate.model, updateService: appDelegate.updateService)
        }

        Settings {
            SettingsView(model: appDelegate.model, updateService: appDelegate.updateService)
        }
    }
}
