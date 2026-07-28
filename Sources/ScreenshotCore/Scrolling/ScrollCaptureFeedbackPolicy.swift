public enum ScrollCaptureFeedbackState: Equatable, Sendable {
    case ready
    case aligning
    case acceptedDown
    case acceptedUp
    case needsOverlap
}

public enum ScrollCaptureFeedbackPolicy {
    public static func state(for outcome: ScrollFrameSettleOutcome) -> ScrollCaptureFeedbackState {
        switch outcome {
        case .unchanged:
            return .ready
        case .pending:
            return .aligning
        case let .commit(decision):
            return state(for: decision)
        case .insufficientOverlap:
            return .needsOverlap
        }
    }

    public static func state(for decision: ScrollFrameDecision) -> ScrollCaptureFeedbackState {
        switch decision {
        case .unchanged:
            return .ready
        case .append:
            return .acceptedDown
        case .prepend:
            return .acceptedUp
        case .insufficientOverlap:
            return .needsOverlap
        }
    }
}
