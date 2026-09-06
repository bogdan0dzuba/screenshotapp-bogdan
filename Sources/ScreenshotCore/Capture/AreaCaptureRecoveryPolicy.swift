public enum AreaCaptureRecoveryAction: Equatable, Sendable {
    case start
    case waitForRecovery
    case cancelAndRestart
}

public enum AreaCaptureRecoveryPolicy {
    public static let forcedRecoveryAttemptCount = 3

    public static func action(
        hasActiveAreaCapture: Bool,
        hotKeyAttemptCount: Int
    ) -> AreaCaptureRecoveryAction {
        guard hasActiveAreaCapture else { return .start }
        return hotKeyAttemptCount >= forcedRecoveryAttemptCount
            ? .cancelAndRestart
            : .waitForRecovery
    }
}
