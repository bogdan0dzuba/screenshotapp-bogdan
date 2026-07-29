import CoreGraphics
import Foundation

public enum ScrollStitcherError: LocalizedError {
    case noFrames
    case differentWidths
    case invalidOverlaps
    case contextCreationFailed

    public var errorDescription: String? {
        switch self {
        case .noFrames: "Нет кадров для склейки"
        case .differentWidths: "Кадры прокрутки имеют разную ширину"
        case .invalidOverlaps: "Не удалось подтвердить границы кадров"
        case .contextCreationFailed: "Не удалось подготовить изображение"
        }
    }
}

public enum ScrollStitchSeam: Equatable, Sendable {
    case append(overlap: Int)
    case prepend(overlap: Int)

    public var overlap: Int {
        switch self {
        case let .append(overlap), let .prepend(overlap):
            overlap
        }
    }
}

public enum ScrollStitcher {
    public static func stitch(_ frames: [CGImage]) throws -> CGImage {
        try stitch(frames, direction: .down)
    }

    /// Восстанавливает перекрытия, когда подтверждённые seams потеряны.
    /// Направление обязательно, иначе кадры, снятые вверх, склеиваются как «вниз»
    /// и у полного первого кадра срезается верх.
    public static func stitch(
        _ frames: [CGImage],
        direction: ScrollCaptureDirection
    ) throws -> CGImage {
        guard let first = frames.first else { throw ScrollStitcherError.noFrames }
        guard frames.allSatisfy({ $0.width == first.width }) else {
            throw ScrollStitcherError.differentWidths
        }
        guard frames.count > 1 else { return first }

        let grayFrames = try frames.map(grayImage)
        var seams: [ScrollStitchSeam] = []
        for index in 1..<grayFrames.count {
            let match = try OverlapMatcher.bestVerticalMatch(
                previous: grayFrames[index - 1],
                next: grayFrames[index]
            )
            let limit = max(0, min(frames[index - 1].height, frames[index].height) - 1)
            let matched = match.meanDifference <= 28
            switch direction {
            case .down:
                seams.append(.append(overlap: matched ? min(match.overlap, limit) : 0))
            case .up:
                seams.append(.prepend(overlap: matched ? min(match.contentOverlap, limit) : 0))
            }
        }
        return try stitch(frames, seams: seams)
    }

    public static func stitch(_ frames: [CGImage], overlaps: [Int]) throws -> CGImage {
        try stitch(frames, seams: overlaps.map { .append(overlap: $0) })
    }

    public static func stitch(_ frames: [CGImage], seams: [ScrollStitchSeam]) throws -> CGImage {
        guard let first = frames.first else { throw ScrollStitcherError.noFrames }
        guard frames.allSatisfy({ $0.width == first.width }) else {
            throw ScrollStitcherError.differentWidths
        }
        guard seams.count == max(0, frames.count - 1) else {
            throw ScrollStitcherError.invalidOverlaps
        }
        for (index, seam) in seams.enumerated() {
            let maximumOverlap = min(frames[index].height, frames[index + 1].height)
            guard seam.overlap >= 0, seam.overlap < maximumOverlap else {
                throw ScrollStitcherError.invalidOverlaps
            }
        }
        guard frames.count > 1 else { return first }

        let isAppend = seams.allSatisfy {
            if case .append = $0 { return true }
            return false
        }
        let isPrepend = seams.allSatisfy {
            if case .prepend = $0 { return true }
            return false
        }
        guard isAppend || isPrepend else {
            throw ScrollStitcherError.invalidOverlaps
        }

        let slices: [CGImage] = try frames.enumerated().map { index, frame in
            let cropRect: CGRect
            if isAppend, index > 0 {
                let overlap = seams[index - 1].overlap
                cropRect = CGRect(
                    x: 0,
                    y: overlap,
                    width: frame.width,
                    height: frame.height - overlap
                )
            } else if isPrepend, index < seams.count {
                let overlap = seams[index].overlap
                cropRect = CGRect(
                    x: 0,
                    y: 0,
                    width: frame.width,
                    height: frame.height - overlap
                )
            } else {
                return frame
            }
            guard let slice = frame.cropping(to: cropRect) else {
                throw ScrollStitcherError.contextCreationFailed
            }
            return slice
        }
        let totalHeight = slices.reduce(0) { $0 + $1.height }
        guard let context = CGContext(
            data: nil,
            width: first.width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: first.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScrollStitcherError.contextCreationFailed
        }

        var y = totalHeight
        for slice in slices {
            y -= slice.height
            context.draw(slice, in: CGRect(x: 0, y: y, width: slice.width, height: slice.height))
        }

        guard let image = context.makeImage() else {
            throw ScrollStitcherError.contextCreationFailed
        }
        return image
    }

    public static func grayImage(from image: CGImage) throws -> GrayImage {
        let sampleWidth = min(96, image.width)
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: sampleWidth * height)
        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw ScrollStitcherError.contextCreationFailed
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: height))
        return GrayImage(width: sampleWidth, height: height, pixels: pixels)
    }
}
