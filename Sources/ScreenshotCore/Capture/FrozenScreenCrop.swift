import CoreGraphics

public enum FrozenScreenCrop {
    public static func pixelRect(
        selection: CGRect,
        viewSize: CGSize,
        imagePixelSize: CGSize
    ) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0,
              imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return .zero
        }
        let scaleX = imagePixelSize.width / viewSize.width
        let scaleY = imagePixelSize.height / viewSize.height
        let scaled = CGRect(
            x: selection.minX * scaleX,
            y: selection.minY * scaleY,
            width: selection.width * scaleX,
            height: selection.height * scaleY
        ).integral
        return scaled.intersection(CGRect(origin: .zero, size: imagePixelSize))
    }
}
