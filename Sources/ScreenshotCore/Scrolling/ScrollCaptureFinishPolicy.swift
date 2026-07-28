public enum ScrollCaptureFinishPolicy {
    public static func canFinish(isCapturing: Bool, isFinalizing: Bool) -> Bool {
        isCapturing && !isFinalizing
    }
}
