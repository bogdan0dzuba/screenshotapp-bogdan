public enum AreaCaptureRecoveryAction: Equatable, Sendable {
    case start
    case cancelAndRestart
}

public enum AreaCaptureRecoveryPolicy {
    public static func action(hasActiveAreaCapture: Bool) -> AreaCaptureRecoveryAction {
        hasActiveAreaCapture ? .cancelAndRestart : .start
    }
}
