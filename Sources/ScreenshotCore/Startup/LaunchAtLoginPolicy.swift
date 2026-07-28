import Foundation

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

public enum LaunchAtLoginAction: Equatable, Sendable {
    case none
    case register
    case unregister
}

public enum LaunchAtLoginPolicy {
    public static func action(
        desiredEnabled: Bool,
        status: LaunchAtLoginStatus
    ) -> LaunchAtLoginAction {
        if desiredEnabled {
            return status == .notRegistered || status == .notFound ? .register : .none
        }
        return status == .enabled || status == .requiresApproval ? .unregister : .none
    }

    public static func isEnabled(status: LaunchAtLoginStatus) -> Bool {
        status == .enabled
    }

    public static func statusMessage(status: LaunchAtLoginStatus) -> String? {
        switch status {
        case .requiresApproval:
            "Разрешите автозапуск в системных настройках macOS."
        case .notFound:
            "macOS не нашла приложение среди объектов входа."
        case .notRegistered, .enabled:
            nil
        }
    }

    public static func diagnosticValue(status: LaunchAtLoginStatus) -> String {
        switch status {
        case .notRegistered:
            "notRegistered"
        case .enabled:
            "enabled"
        case .requiresApproval:
            "requiresApproval"
        case .notFound:
            "notFound"
        }
    }
}

public enum LaunchAtLoginDefaultsMigration {
    private static let markerKey = "ScreenshotApp.didEnableLaunchAtLoginV2"

    public static func shouldEnableLaunchAtLogin(in defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: markerKey)
    }

    public static func markLaunchAtLoginHandled(in defaults: UserDefaults) {
        defaults.set(true, forKey: markerKey)
    }
}
