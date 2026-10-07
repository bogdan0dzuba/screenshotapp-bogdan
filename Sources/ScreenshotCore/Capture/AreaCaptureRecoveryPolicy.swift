public enum AreaCaptureRecoveryAction: Equatable, Sendable {
    case start
    case refocus
    case waitForRecovery
    case cancelAndRestart
}

public enum AreaCaptureRecoveryPolicy {
    public static let forcedRecoveryAttemptCount = 3

    public static func action(
        hasActiveAreaCapture: Bool,
        hotKeyAttemptCount: Int,
        hasPendingSelection: Bool = false
    ) -> AreaCaptureRecoveryAction {
        guard hasActiveAreaCapture else { return .start }
        if hotKeyAttemptCount >= forcedRecoveryAttemptCount { return .cancelAndRestart }
        return hasPendingSelection ? .refocus : .waitForRecovery
    }
}
