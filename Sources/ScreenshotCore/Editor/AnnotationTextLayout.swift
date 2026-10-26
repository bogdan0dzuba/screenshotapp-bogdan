import AppKit

public enum AnnotationTextLayout {
    /// Text bounds in source-image pixels, with the origin at the top left.
    public static func bounds(for annotation: Annotation, canvasSize: CanvasSize) -> CGRect? {
        guard annotation.kind == .text, let point = annotation.points.first,
              canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let font = NSFont.systemFont(ofSize: annotation.style.fontSize, weight: .semibold)
        let text = annotation.text.flatMap { $0.isEmpty ? nil : $0 } ?? " "
        let size = NSAttributedString(string: text, attributes: [.font: font]).size()
        return CGRect(
            x: point.x * canvasSize.width,
            y: point.y * canvasSize.height + annotation.style.fontSize - size.height,
            width: max(size.width, annotation.style.fontSize / 2),
            height: size.height
        )
    }
}
