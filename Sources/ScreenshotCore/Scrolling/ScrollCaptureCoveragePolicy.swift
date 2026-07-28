public enum ScrollCaptureCoverageEdge: Equatable, Sendable {
    case top
    case bottom
}

public struct ScrollCaptureCoverage: Equatable, Sendable {
    public var alreadyCapturedEdge: ScrollCaptureCoverageEdge
    public var alreadyCapturedFraction: Double

    public init(
        alreadyCapturedEdge: ScrollCaptureCoverageEdge,
        alreadyCapturedFraction: Double
    ) {
        self.alreadyCapturedEdge = alreadyCapturedEdge
        self.alreadyCapturedFraction = min(max(alreadyCapturedFraction, 0), 1)
    }
}

public enum ScrollCaptureCoveragePolicy {
    public static func coverage(
        for decision: ScrollFrameDecision,
        frameHeight: Int
    ) -> ScrollCaptureCoverage? {
        guard frameHeight > 0 else { return nil }
        switch decision {
        case let .append(overlap):
            return ScrollCaptureCoverage(
                alreadyCapturedEdge: .top,
                alreadyCapturedFraction: Double(overlap) / Double(frameHeight)
            )
        case let .prepend(overlap):
            return ScrollCaptureCoverage(
                alreadyCapturedEdge: .bottom,
                alreadyCapturedFraction: Double(overlap) / Double(frameHeight)
            )
        case .unchanged, .insufficientOverlap:
            return nil
        }
    }

    public static func capturedViewport(
        alreadyCapturedEdge: ScrollCaptureCoverageEdge
    ) -> ScrollCaptureCoverage {
        ScrollCaptureCoverage(
            alreadyCapturedEdge: alreadyCapturedEdge,
            alreadyCapturedFraction: 1
        )
    }
}
