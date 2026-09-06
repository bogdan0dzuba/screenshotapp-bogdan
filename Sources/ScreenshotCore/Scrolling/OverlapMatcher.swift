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
    /// Совпадающие строки целиком: закреплённая верхняя полоса плюс совпавшее содержимое.
    public var overlap: Int
    public var meanDifference: Double
    /// Часть `overlap`, которую занимает закреплённая верхняя полоса обоих кадров.
    public var fixedTopRows: Int

    /// Строки, которые действительно повторяют содержимое соседнего кадра.
    /// Именно их нужно убирать снизу верхнего кадра при склейке вверх.
    public var contentOverlap: Int { max(0, overlap - fixedTopRows) }

    public init(overlap: Int, meanDifference: Double, fixedTopRows: Int = 0) {
        self.overlap = overlap
        self.meanDifference = meanDifference
        self.fixedTopRows = fixedTopRows
    }
}

public enum OverlapMatcher {
    public static func bestVerticalOverlap(previous: GrayImage, next: GrayImage) throws -> Int {
        let match = try bestVerticalMatch(previous: previous, next: next)
        guard match.meanDifference <= 28 else { return 0 }
        return min(match.overlap, max(0, min(previous.height, next.height) - 1))
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

        let commonHeight = min(previous.height, next.height)
        let fixedTopRows = matchingTopBandRows(previous: previous, next: next)
        let contentHeight = commonHeight - fixedTopRows
        // Верхняя граница включает contentHeight, иначе неподвижный viewport
        // невозможно распознать и слегка изменившийся кадр без прокрутки
        // ошибочно объявляется потерей перекрытия.
        let maximum = contentHeight
        guard maximum > 0 else {
            return VerticalOverlapMatch(overlap: 0, meanDifference: .infinity)
        }

        var bestOverlap = 0
        var bestScore = Double.infinity
        func score(
            for contentOverlap: Int,
            rowSampleLimit: Int,
            columnSampleLimit: Int
        ) -> Double? {
            let previousStart = previous.height - contentOverlap
            let nextStart = fixedTopRows
            let rowStride = max(1, contentOverlap / max(1, rowSampleLimit))
            let columnStride = max(1, previous.width / max(1, columnSampleLimit))
            var difference: Int64 = 0
            var sampled = 0
            var compared = 0
            for row in stride(from: 0, to: contentOverlap, by: rowStride) {
                let previousOffset = (previousStart + row) * previous.width
                let nextOffset = (nextStart + row) * next.width
                for column in stride(from: 0, to: previous.width, by: columnStride) {
                    sampled += 1
                    let previousContrast = localContrast(
                        in: previous,
                        row: previousStart + row,
                        column: column
                    )
                    let nextContrast = localContrast(
                        in: next,
                        row: nextStart + row,
                        column: column
                    )
                    guard max(previousContrast, nextContrast) >= 8 else { continue }
                    difference += Int64(
                        abs(Int(previous.pixels[previousOffset + column]) - Int(next.pixels[nextOffset + column]))
                    )
                    compared += 1
                }
            }
            let minimumInformativeSamples = min(sampled, max(8, sampled / 50))
            guard compared >= minimumInformativeSamples else { return nil }
            return Double(difference) / Double(compared)
        }

        func consider(_ contentOverlap: Int) {
            guard let score = score(
                for: contentOverlap,
                rowSampleLimit: 64,
                columnSampleLimit: 48
            ) else { return }
            let fullFrameOverlap = fixedTopRows + contentOverlap
            if score < bestScore || (score == bestScore && fullFrameOverlap > bestOverlap) {
                bestScore = score
                bestOverlap = fullFrameOverlap
            }
        }

        if maximum <= 256 {
            for contentOverlap in 1...maximum {
                consider(contentOverlap)
            }
        } else {
            // Every possible seam is still considered, but the first pass samples
            // only a small grid. This keeps a sharp one-row match discoverable;
            // coarse-only candidate positions can skip it on dense content.
            var quickCandidates: [(contentOverlap: Int, score: Double)] = []
            quickCandidates.reserveCapacity(maximum)
            for contentOverlap in 1...maximum {
                guard let quickScore = score(
                    for: contentOverlap,
                    rowSampleLimit: 16,
                    columnSampleLimit: 16
                ) else { continue }
                quickCandidates.append((contentOverlap, quickScore))
            }
            quickCandidates.sort {
                if $0.score != $1.score { return $0.score < $1.score }
                return $0.contentOverlap > $1.contentOverlap
            }
            for candidate in quickCandidates.prefix(48) {
                consider(candidate.contentOverlap)
            }
            // Keep boundary behavior identical when all quick samples are
            // uninformative or tie on a flat viewport.
            consider(1)
            consider(maximum)
        }

        return VerticalOverlapMatch(
            overlap: bestOverlap,
            meanDifference: bestScore,
            fixedTopRows: bestOverlap > 0 ? fixedTopRows : 0
        )
    }

    private static func matchingTopBandRows(previous: GrayImage, next: GrayImage) -> Int {
        let maximumBandHeight = min(previous.height, next.height) / 3
        guard maximumBandHeight > 0 else { return 0 }

        let columnStride = max(1, previous.width / 48)
        var matchingRows = 0
        var sampled = 0
        var informative = 0
        for row in 0..<maximumBandHeight {
            let previousOffset = row * previous.width
            let nextOffset = row * next.width
            var difference = 0
            var compared = 0
            for column in stride(from: 0, to: previous.width, by: columnStride) {
                sampled += 1
                difference += abs(
                    Int(previous.pixels[previousOffset + column]) - Int(next.pixels[nextOffset + column])
                )
                if max(
                    localContrast(in: previous, row: row, column: column),
                    localContrast(in: next, row: row, column: column)
                ) >= 8 {
                    informative += 1
                }
                compared += 1
            }
            guard Double(difference) / Double(compared) <= 6 else { break }
            matchingRows = row + 1
        }
        let minimumInformativeSamples = min(sampled, max(8, sampled / 50))
        return informative >= minimumInformativeSamples ? matchingRows : 0
    }

    private static func localContrast(
        in image: GrayImage,
        row: Int,
        column: Int
    ) -> Int {
        let value = Int(image.pixels[row * image.width + column])
        var contrast = 0
        if row > 0 {
            contrast = max(
                contrast,
                abs(value - Int(image.pixels[(row - 1) * image.width + column]))
            )
        }
        if row + 1 < image.height {
            contrast = max(
                contrast,
                abs(value - Int(image.pixels[(row + 1) * image.width + column]))
            )
        }
        if column > 0 {
            contrast = max(
                contrast,
                abs(value - Int(image.pixels[row * image.width + column - 1]))
            )
        }
        if column + 1 < image.width {
            contrast = max(
                contrast,
                abs(value - Int(image.pixels[row * image.width + column + 1]))
            )
        }
        return contrast
    }
}
