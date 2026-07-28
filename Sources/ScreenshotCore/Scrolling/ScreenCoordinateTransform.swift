import CoreGraphics

public enum ScreenCoordinateTransform {
    public static func appKitRect(
        fromCaptureRect rect: CGRect,
        mainScreenTop: CGFloat
    ) -> CGRect {
        CGRect(
            x: rect.minX,
            y: mainScreenTop - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    public static func captureRect(
        fromAppKitRect rect: CGRect,
        mainScreenTop: CGFloat
    ) -> CGRect {
        CGRect(
            x: rect.minX,
            y: mainScreenTop - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
