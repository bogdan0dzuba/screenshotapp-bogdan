import CoreGraphics
import Foundation

public enum ScrollStitcherError: LocalizedError {
    case noFrames
    case differentWidths
    case contextCreationFailed

    public var errorDescription: String? {
        switch self {
        case .noFrames: "Нет кадров для склейки"
        case .differentWidths: "Кадры прокрутки имеют разную ширину"
        case .contextCreationFailed: "Не удалось подготовить изображение"
        }
    }
}

public enum ScrollStitcher {
    public static func stitch(_ frames: [CGImage]) throws -> CGImage {
        guard let first = frames.first else { throw ScrollStitcherError.noFrames }
        guard frames.allSatisfy({ $0.width == first.width }) else {
            throw ScrollStitcherError.differentWidths
        }
        guard frames.count > 1 else { return first }

        let grayFrames = try frames.map(grayImage)
        var overlaps: [Int] = []
        for index in 1..<grayFrames.count {
            overlaps.append(
                try OverlapMatcher.bestVerticalOverlap(
                    previous: grayFrames[index - 1],
                    next: grayFrames[index]
                )
            )
        }

        let totalHeight = first.height + zip(frames.dropFirst(), overlaps).reduce(0) { partial, pair in
            partial + pair.0.height - pair.1
        }
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

        var y = totalHeight - first.height
        context.draw(first, in: CGRect(x: 0, y: y, width: first.width, height: first.height))
        for (index, frame) in frames.dropFirst().enumerated() {
            y -= frame.height - overlaps[index]
            context.draw(frame, in: CGRect(x: 0, y: y, width: frame.width, height: frame.height))
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
