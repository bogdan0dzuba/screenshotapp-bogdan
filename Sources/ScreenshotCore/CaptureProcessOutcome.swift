public enum CaptureProcessOutcome: Equatable {
    case success
    case cancelled
    case missingOutput
    case failed(Int32)

    public static func resolve(terminationStatus: Int32, outputExists: Bool, isInteractive: Bool) -> Self {
        if isInteractive, !outputExists, terminationStatus == 0 || terminationStatus == 1 {
            return .cancelled
        }
        if terminationStatus == 0 {
            return outputExists ? .success : .missingOutput
        }
        return .failed(terminationStatus)
    }
}
