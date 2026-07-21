import AppKit
import Sparkle

@MainActor
final class UpdateService: ObservableObject {
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

    init() {
        let userDriverDelegate = UpdateUserDriverDelegate()
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: userDriverDelegate
        )
        self.userDriverDelegate = userDriverDelegate
        updaterController = controller
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

private final class UpdateUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
