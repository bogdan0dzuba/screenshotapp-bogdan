import CoreGraphics

public enum ScrollCapturePreviewCanvasError: Error {
    case contextCreationFailed
    case sliceCreationFailed
}

/// Накапливает уменьшенное превью будущей склейки прямо во время съёмки.
///
/// Полный растр не трогается: на каждый принятый кадр добавляется только новый срез,
/// уже приведённый к ширине превью. Порядок срезов повторяет порядок кадров в
/// `ScrollCaptureSession`, поэтому превью показывает именно то, что окажется в PNG.
public struct ScrollCapturePreviewCanvas {
    public private(set) var width: Int
    private var slices: [CGImage] = []
    private var additions: [ScrollCaptureDirection] = []

    public var isEmpty: Bool { slices.isEmpty }
    public var sliceCount: Int { slices.count }
    public var totalHeight: Int { slices.reduce(0) { $0 + $1.height } }

    public init(width: Int = 440) {
        self.width = max(1, width)
    }

    /// Первый кадр попадает в превью целиком - он же целиком попадает в итоговый PNG.
    public mutating func start(with frame: CGImage) throws {
        slices = [try scaled(frame)]
        additions = []
    }

    /// Прокрутка вниз: снизу дорисовываются только новые строки кадра.
    public mutating func append(frame: CGImage, overlap: Int) throws {
        guard let slice = try newRows(of: frame, overlap: overlap, keepingTop: false) else { return }
        slices.append(slice)
        additions.append(.down)
    }

    /// Прокрутка вверх: сверху дорисовываются только новые строки кадра.
    public mutating func prepend(frame: CGImage, overlap: Int) throws {
        guard let slice = try newRows(of: frame, overlap: overlap, keepingTop: true) else { return }
        slices.insert(slice, at: 0)
        additions.append(.up)
    }

    public mutating func undoLast() {
        guard let direction = additions.popLast() else { return }
        switch direction {
        case .down: if slices.count > 1 { slices.removeLast() }
        case .up: if slices.count > 1 { slices.removeFirst() }
        }
    }

    public mutating func reset() {
        slices.removeAll()
        additions.removeAll()
    }

    /// Собирает превью в одно изображение. Возвращает nil, пока не принят ни один кадр.
    public func composed() throws -> CGImage? {
        guard !slices.isEmpty else { return nil }
        let height = totalHeight
        guard height > 0, let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScrollCapturePreviewCanvasError.contextCreationFailed
        }
        var y = height
        for slice in slices {
            y -= slice.height
            context.draw(slice, in: CGRect(x: 0, y: y, width: width, height: slice.height))
        }
        guard let image = context.makeImage() else {
            throw ScrollCapturePreviewCanvasError.contextCreationFailed
        }
        return image
    }

    private mutating func newRows(
        of frame: CGImage,
        overlap: Int,
        keepingTop: Bool
    ) throws -> CGImage? {
        let newHeight = frame.height - max(0, overlap)
        guard newHeight > 0 else { return nil }
        // CGImage.cropping работает от левого верхнего угла: вниз новые строки снизу,
        // вверх - сверху.
        let cropRect = CGRect(
            x: 0,
            y: keepingTop ? 0 : max(0, overlap),
            width: frame.width,
            height: newHeight
        )
        guard let slice = frame.cropping(to: cropRect) else {
            throw ScrollCapturePreviewCanvasError.sliceCreationFailed
        }
        return try scaled(slice)
    }

    private func scaled(_ image: CGImage) throws -> CGImage {
        guard image.width != width else { return image }
        let height = max(1, Int((CGFloat(image.height) * CGFloat(width) / CGFloat(image.width)).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScrollCapturePreviewCanvasError.contextCreationFailed
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else {
            throw ScrollCapturePreviewCanvasError.contextCreationFailed
        }
        return scaled
    }
}
