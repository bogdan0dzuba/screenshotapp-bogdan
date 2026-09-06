import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updateService = UpdateService()
    let launchAtLoginService = LaunchAtLoginService()
    private var settingsController: SettingsWindowController?
    private let installationCoordinator = ApplicationInstallationCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if installationCoordinator.offerInstallationIfNeeded() { return }
        launchAtLoginService.enableByDefaultOnce()
        settingsController = SettingsWindowController(
            model: model,
            updateService: updateService,
            launchAtLoginService: launchAtLoginService
        )
        let shelf = ShelfPanelController(model: model, onOpenSettings: { [weak self] in
            self?.showSettings()
        })
        model.shelfController = shelf
        model.editorController = EditorWindowController()
        model.pinnedController = PinnedImageController()
        model.regionSelectionController = RegionSelectionController()
        model.scrollCaptureController = ScrollCaptureController()
        model.start()
        updateService.startUpdaterAndCheckAtLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.regionSelectionController?.focusPendingOverlayIfNeeded()
    }

    func showSettings() {
        settingsController?.show()
    }
}
