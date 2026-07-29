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
        if isSameViewport(previous, next) {
            return .unchanged
        }
        let appendMatch = try OverlapMatcher.bestVerticalMatch(previous: previous, next: next)
        let prependMatch = try OverlapMatcher.bestVerticalMatch(previous: next, next: previous)
        // При склейке вниз обрезается верх нижнего кадра, поэтому убирается и закреплённая
        // полоса. При склейке вверх нижний кадр остаётся целым, поэтому снизу верхнего кадра
        // убирается только реально повторяющееся содержимое.
        let candidates: [(decision: ScrollFrameDecision, match: VerticalOverlapMatch, newRows: Int)] = [
            (.append(overlap: appendMatch.overlap), appendMatch, next.height - appendMatch.overlap),
            (
                .prepend(overlap: prependMatch.contentOverlap),
                prependMatch,
                next.height - prependMatch.overlap
            ),
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

    private static func isSameViewport(_ previous: GrayImage, _ next: GrayImage) -> Bool {
        guard previous.width == next.width,
              previous.height == next.height,
              previous.pixels.count == next.pixels.count,
              !previous.pixels.isEmpty else {
            return false
        }
        let stride = max(1, previous.pixels.count / 8_192)
        var difference: Int64 = 0
        var compared = 0
        for index in Swift.stride(from: 0, to: previous.pixels.count, by: stride) {
            difference += Int64(abs(Int(previous.pixels[index]) - Int(next.pixels[index])))
            compared += 1
        }
        return Double(difference) / Double(compared) <= 2
    }
}
