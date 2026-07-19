public struct ScrollFramePolicy: Equatable, Sendable {
    public var minimumNewRows: Int
    public var minimumOverlapRows: Int
    public var maximumMeanDifference: Double

    public init(
        minimumNewRows: Int,
        minimumOverlapRows: Int,
        maximumMeanDifference: Double
    ) {
        self.minimumNewRows = max(1, minimumNewRows)
        self.minimumOverlapRows = max(1, minimumOverlapRows)
        self.maximumMeanDifference = maximumMeanDifference
    }

    public init(frameHeight: Int) {
        self.init(
            minimumNewRows: max(2, frameHeight / 10),
            minimumOverlapRows: max(2, frameHeight / 12),
            maximumMeanDifference: 28
        )
    }
}

public enum ScrollFrameDecision: Equatable, Sendable {
    case unchanged
    case append(overlap: Int)
    case prepend(overlap: Int)
    case insufficientOverlap
}

public enum ScrollFrameClassifier {
    public static func decision(
        previous: GrayImage,
        next: GrayImage,
        policy: ScrollFramePolicy
    ) throws -> ScrollFrameDecision {
        let appendMatch = try OverlapMatcher.bestVerticalMatch(previous: previous, next: next)
        let prependMatch = try OverlapMatcher.bestVerticalMatch(previous: next, next: previous)
        let candidates: [(decision: ScrollFrameDecision, match: VerticalOverlapMatch, newRows: Int)] = [
            (.append(overlap: appendMatch.overlap), appendMatch, next.height - appendMatch.overlap),
            (.prepend(overlap: prependMatch.overlap), prependMatch, next.height - prependMatch.overlap),
        ]
        let stitchable = candidates.filter {
            $0.match.meanDifference <= policy.maximumMeanDifference
                && $0.match.overlap >= policy.minimumOverlapRows
        }
        guard !stitchable.isEmpty else { return .insufficientOverlap }
        let changed = stitchable.filter { $0.newRows >= policy.minimumNewRows }
        guard !changed.isEmpty else { return .unchanged }
        return changed.min {
            if $0.match.meanDifference != $1.match.meanDifference {
                return $0.match.meanDifference < $1.match.meanDifference
            }
            return $0.match.overlap > $1.match.overlap
        }!.decision
    }
}
