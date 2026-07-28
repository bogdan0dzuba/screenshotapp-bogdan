public enum ScrollCaptureStartPolicy {
    public static func canStart(
        hasStarted: Bool,
        isProcessingFrame: Bool
    ) -> Bool {
        !hasStarted && !isProcessingFrame
    }
}
