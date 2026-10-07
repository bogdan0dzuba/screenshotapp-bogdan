import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updateService = UpdateService()
    let launchAtLoginService = LaunchAtLoginService()
    private var settingsController: SettingsWindowController?
    private var didInitialize = false
    private var statusItem: NSStatusItem?
    private let installationCoordinator = ApplicationInstallationCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if installationCoordinator.offerInstallationIfNeeded(onLaunchFailure: { [weak self] in
            self?.initializeApplication()
        }) { return }
        initializeApplication()
    }

    private func initializeApplication() {
        guard !didInitialize else { return }
        didInitialize = true
        CaptureTelemetry.logger.info("startup_initialized os=\(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public) version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown", privacy: .public)")
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
        installStatusMenu()
        updateService.startUpdaterAndCheckAtLaunch()
    }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: AppIdentity.displayName)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "\(AppIdentity.displayName) - \(AppIdentity.versionDescription)"
        item.button?.setAccessibilityLabel(AppIdentity.displayName)
        let menu = NSMenu()
        let version = NSMenuItem(title: AppIdentity.versionDescription, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())
        for (title, action) in [
            ("Снимок области", #selector(captureAreaFromMenu)),
            ("Показать полку", #selector(revealShelfFromMenu)),
            ("Настройки…", #selector(showSettings)),
            ("Завершить \(AppIdentity.displayName)", #selector(quitFromMenu)),
        ] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        item.menu = menu
        statusItem = item
    }

    @objc private func captureAreaFromMenu() { model.capture(.area) }
    @objc private func revealShelfFromMenu() { model.revealShelf() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard didInitialize else { return false }
        if model.regionSelectionController?.hasPendingSelection == true {
            model.regionSelectionController?.focusPendingOverlayIfNeeded()
        } else {
            model.revealShelf()
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.regionSelectionController?.focusPendingOverlayIfNeeded()
    }

    @objc func showSettings() {
        settingsController?.show()
    }
}
