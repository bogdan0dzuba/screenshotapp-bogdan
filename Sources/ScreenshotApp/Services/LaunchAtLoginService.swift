import Combine
import OSLog
import ServiceManagement
import ScreenshotCore

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    private let appService: SMAppService
    private let defaults: UserDefaults
    private let logger = Logger(
        subsystem: "local.codex.ScreenshotApp",
        category: "LaunchAtLogin"
    )

    init(
        appService: SMAppService = SMAppService.mainApp,
        defaults: UserDefaults = .standard
    ) {
        self.appService = appService
        self.defaults = defaults
        refresh()
    }

    func enableByDefaultOnce() {
        guard LaunchAtLoginDefaultsMigration.shouldEnableLaunchAtLogin(in: defaults) else {
            refresh()
            return
        }
        if setEnabled(true) {
            LaunchAtLoginDefaultsMigration.markLaunchAtLoginHandled(in: defaults)
        }
    }

    @discardableResult
    func setEnabled(_ desiredEnabled: Bool) -> Bool {
        let currentStatus = normalizedStatus
        let action = LaunchAtLoginPolicy.action(
            desiredEnabled: desiredEnabled,
            status: currentStatus
        )
        do {
            switch action {
            case .register:
                try appService.register()
            case .unregister:
                try appService.unregister()
            case .none:
                break
            }
            refresh()
            if desiredEnabled {
                return action == .register
                    || normalizedStatus == .enabled
                    || normalizedStatus == .requiresApproval
            }
            return true
        } catch {
            refresh(errorDescription: error.localizedDescription)
            logger.error(
                "desiredEnabled=\(desiredEnabled, privacy: .public), status=\(LaunchAtLoginPolicy.diagnosticValue(status: currentStatus), privacy: .public), error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    func refresh() {
        refresh(errorDescription: nil)
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private var normalizedStatus: LaunchAtLoginStatus {
        switch appService.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }

    private func refresh(errorDescription: String? = nil) {
        let status = normalizedStatus
        isEnabled = LaunchAtLoginPolicy.isEnabled(status: status)
        statusMessage = errorDescription ?? LaunchAtLoginPolicy.statusMessage(status: status)
        logger.info(
            "status=\(LaunchAtLoginPolicy.diagnosticValue(status: status), privacy: .public)"
        )
    }
}
