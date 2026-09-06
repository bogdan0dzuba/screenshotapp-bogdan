import Foundation

public enum SelectionSizeLabelPlacement {
    private static let pointerGap: CGFloat = 12
    private static let screenMargin: CGFloat = 6

    public static func origin(near pointer: CGPoint, labelSize: CGSize, in bounds: CGRect) -> CGPoint {
        let right = pointer.x + pointerGap
        let x = right + labelSize.width + screenMargin <= bounds.maxX
            ? right
            : pointer.x - labelSize.width - pointerGap

        let below = pointer.y + pointerGap
        let y = below + labelSize.height + screenMargin <= bounds.maxY
            ? below
            : pointer.y - labelSize.height - pointerGap

        return CGPoint(
            x: min(max(x, bounds.minX + screenMargin), bounds.maxX - labelSize.width - screenMargin),
            y: min(max(y, bounds.minY + screenMargin), bounds.maxY - labelSize.height - screenMargin)
        )
    }
}
