public enum CaptureProcessOutcome: Equatable {
    case success
    case cancelled
    case failed(Int32)

    public static func resolve(terminationStatus: Int32, outputExists: Bool) -> Self {
        if terminationStatus == 0 {
            return outputExists ? .success : .cancelled
        }
        if terminationStatus == 1, !outputExists {
            return .cancelled
        }
        return .failed(terminationStatus)
    }
}
