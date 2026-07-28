import CoreGraphics

public enum ScrollFrameNormalizerError: Error {
    case contextCreationFailed
    case imageCreationFailed
}

public enum ScrollFrameNormalizer {
    public static func normalized(
        _ image: CGImage,
        width: Int,
        height: Int
    ) throws -> CGImage {
        guard image.width != width || image.height != height else { return image }
        guard width > 0,
              height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ScrollFrameNormalizerError.contextCreationFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let normalized = context.makeImage() else {
            throw ScrollFrameNormalizerError.imageCreationFailed
        }
        return normalized
    }
}
