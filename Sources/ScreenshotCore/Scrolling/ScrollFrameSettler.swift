public enum ScrollFrameSettleOutcome: Equatable, Sendable {
    case unchanged
    case pending(ScrollFrameDecision)
    case commit(ScrollFrameDecision)
    case insufficientOverlap
}

public struct ScrollFrameSettler: Sendable {
    private var pendingFrame: GrayImage?
    private var pendingSince: Double?
    private let minimumStableDuration: Double

    public init(minimumStableDuration: Double = 0.32) {
        self.minimumStableDuration = max(0, minimumStableDuration)
    }

    public mutating func observe(
        accepted: GrayImage,
        observed: GrayImage,
        policy: ScrollFramePolicy,
        observedAt: Double
    ) throws -> ScrollFrameSettleOutcome {
        let acceptedDecision = try ScrollFrameClassifier.decision(
            previous: accepted,
            next: observed,
            policy: policy
        )

        switch acceptedDecision {
        case .unchanged:
            reset()
            return .unchanged
        case .insufficientOverlap:
            reset()
            return .insufficientOverlap
        case .append, .prepend:
            break
        }

        if let pendingFrame {
            let settlingDecision = try ScrollFrameClassifier.decision(
                previous: pendingFrame,
                next: observed,
                policy: policy
            )
            if settlingDecision == .unchanged {
                let stableDuration = observedAt - (pendingSince ?? observedAt)
                if stableDuration >= minimumStableDuration {
                    reset()
                    return .commit(acceptedDecision)
                }
                return .pending(acceptedDecision)
            }
        }

        pendingFrame = observed
        pendingSince = observedAt
        return .pending(acceptedDecision)
    }

    public mutating func reset() {
        pendingFrame = nil
        pendingSince = nil
    }
}
