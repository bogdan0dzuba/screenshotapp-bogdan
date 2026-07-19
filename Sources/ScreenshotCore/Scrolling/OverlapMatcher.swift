import Foundation

public struct GrayImage: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

public enum OverlapMatcherError: LocalizedError {
    case invalidImage
    case incompatibleWidths

    public var errorDescription: String? {
        switch self {
        case .invalidImage: "Некорректные данные изображения"
        case .incompatibleWidths: "Кадры имеют разную ширину"
        }
    }
}

public struct VerticalOverlapMatch: Equatable, Sendable {
    public var overlap: Int
    public var meanDifference: Double

    public init(overlap: Int, meanDifference: Double) {
        self.overlap = overlap
        self.meanDifference = meanDifference
    }
}

public enum OverlapMatcher {
    public static func bestVerticalOverlap(previous: GrayImage, next: GrayImage) throws -> Int {
        let match = try bestVerticalMatch(previous: previous, next: next)
        return match.meanDifference <= 28 ? match.overlap : 0
    }

    public static func bestVerticalMatch(previous: GrayImage, next: GrayImage) throws -> VerticalOverlapMatch {
        guard previous.width > 0,
              previous.height > 0,
              previous.pixels.count == previous.width * previous.height,
              next.width > 0,
              next.height > 0,
              next.pixels.count == next.width * next.height else {
            throw OverlapMatcherError.invalidImage
        }
        guard previous.width == next.width else {
            throw OverlapMatcherError.incompatibleWidths
        }

        let maximum = min(previous.height, next.height) - 1
        guard maximum > 0 else {
            return VerticalOverlapMatch(overlap: 0, meanDifference: .greatestFiniteMagnitude)
        }

        var bestOverlap = 0
        var bestScore = Double.greatestFiniteMagnitude
        for overlap in 1...maximum {
            let previousStart = previous.height - overlap
            let rowStride = max(1, overlap / 64)
            let columnStride = max(1, previous.width / 48)
            var difference: Int64 = 0
            var compared = 0
            for row in stride(from: 0, to: overlap, by: rowStride) {
                let previousOffset = (previousStart + row) * previous.width
                let nextOffset = row * next.width
                for column in stride(from: 0, to: previous.width, by: columnStride) {
                    difference += Int64(
                        abs(Int(previous.pixels[previousOffset + column]) - Int(next.pixels[nextOffset + column]))
                    )
                    compared += 1
                }
            }
            let score = Double(difference) / Double(compared)
            if score < bestScore || (score == bestScore && overlap > bestOverlap) {
                bestScore = score
                bestOverlap = overlap
            }
        }

        return VerticalOverlapMatch(overlap: bestOverlap, meanDifference: bestScore)
    }
}
