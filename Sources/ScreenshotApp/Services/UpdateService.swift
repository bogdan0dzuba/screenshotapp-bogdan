import AppKit
import ScreenshotCore
import Sparkle

@MainActor
final class UpdateService: ObservableObject {
    private let updaterDelegate: AutomaticUpdateDelegate
    private let userDriverDelegate: UpdateUserDriverDelegate
    private let updaterController: SPUStandardUpdaterController
    private var updaterStarted = false

    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @Published var automaticallyDownloadsUpdates: Bool {
        didSet {
            updaterController.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    init(defaults: UserDefaults = .standard) {
        let updaterDelegate = AutomaticUpdateDelegate()
        let userDriverDelegate = UpdateUserDriverDelegate()
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: userDriverDelegate
        )
        self.updaterDelegate = updaterDelegate
        self.userDriverDelegate = userDriverDelegate
        updaterController = controller

        if AutomaticUpdateDefaultsMigration.shouldEnableAutomaticUpdates(in: defaults) {
            controller.updater.automaticallyChecksForUpdates = true
            controller.updater.automaticallyDownloadsUpdates = true
        }
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
    }

    func startUpdaterAndCheckAtLaunch() {
        guard !updaterStarted else { return }
        updaterController.startUpdater()
        updaterStarted = true

        if automaticallyChecksForUpdates {
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        if !updaterStarted {
            updaterController.startUpdater()
            updaterStarted = true
        }
        updaterController.checkForUpdates(nil)
    }
}

private final class AutomaticUpdateDelegate: NSObject, SPUUpdaterDelegate {
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        immediateInstallHandler()
        return true
    }
}

private final class UpdateUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
