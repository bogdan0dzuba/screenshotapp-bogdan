import AppKit
import CoreGraphics
import CoreImage
import Foundation

public enum AnnotationRendererError: LocalizedError {
    case contextCreationFailed
    case effectCreationFailed

    public var errorDescription: String? {
        switch self {
        case .contextCreationFailed: "Не удалось подготовить редактор изображения"
        case .effectCreationFailed: "Не удалось применить эффект"
        }
    }
}

public enum AnnotationRenderer {
    public static func render(baseImage: CGImage, document: EditorDocument) throws -> CGImage {
        let width = baseImage.width
        let height = baseImage.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AnnotationRendererError.contextCreationFailed
        }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(baseImage, in: bounds)

        for annotation in document.annotations where annotation.kind == .blur || annotation.kind == .pixelate {
            try drawEffect(annotation, baseImage: baseImage, in: context, bounds: bounds)
        }
        for annotation in document.annotations where annotation.kind != .blur && annotation.kind != .pixelate {
            drawVector(annotation, in: context, width: CGFloat(width), height: CGFloat(height))
        }

        guard let output = context.makeImage() else {
            throw AnnotationRendererError.contextCreationFailed
        }
        return output
    }

    private static func drawEffect(
        _ annotation: Annotation,
        baseImage: CGImage,
        in context: CGContext,
        bounds: CGRect
    ) throws {
        guard let normalized = annotation.rect else { return }
        let rect = pixelRect(normalized, width: bounds.width, height: bounds.height)
        let input = CIImage(cgImage: baseImage)
        let output: CIImage
        if annotation.kind == .pixelate {
            output = input.applyingFilter(
                "CIPixellate",
                parameters: [kCIInputScaleKey: max(8, annotation.style.lineWidth * 3)]
            )
        } else {
            output = input
                .clampedToExtent()
                .applyingFilter(
                    "CIGaussianBlur",
                    parameters: [kCIInputRadiusKey: max(10, annotation.style.lineWidth * 2)]
                )
                .cropped(to: input.extent)
        }
        guard let effect = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: input.extent) else {
            throw AnnotationRendererError.effectCreationFailed
        }
        context.saveGState()
        context.clip(to: rect)
        context.draw(effect, in: bounds)
        context.restoreGState()
    }

    private static func drawVector(
        _ annotation: Annotation,
        in context: CGContext,
        width: CGFloat,
        height: CGFloat
    ) {
        let color = cgColor(annotation.style.color)
        context.saveGState()
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(annotation.style.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.kind {
        case .arrow:
            if annotation.points.count >= 2 {
                let start = pixelPoint(annotation.points[0], width: width, height: height)
                let end = pixelPoint(annotation.points[1], width: width, height: height)
                context.move(to: start)
                context.addLine(to: end)
                context.strokePath()
                drawArrowHead(from: start, to: end, in: context, size: max(12, annotation.style.lineWidth * 4))
            }
        case .line:
            if annotation.points.count >= 2 {
                context.move(to: pixelPoint(annotation.points[0], width: width, height: height))
                context.addLine(to: pixelPoint(annotation.points[1], width: width, height: height))
                context.strokePath()
            }
        case .rectangle:
            if let rect = annotation.rect {
                let pixel = pixelRect(rect, width: width, height: height)
                annotation.style.filled ? context.fill(pixel) : context.stroke(pixel)
            }
        case .ellipse:
            if let rect = annotation.rect {
                let pixel = pixelRect(rect, width: width, height: height)
                annotation.style.filled ? context.fillEllipse(in: pixel) : context.strokeEllipse(in: pixel)
            }
        case .pencil, .highlighter:
            if let first = annotation.points.first {
                if annotation.kind == .highlighter {
                    context.setAlpha(0.45)
                    context.setLineWidth(max(12, annotation.style.lineWidth * 3))
                }
                context.move(to: pixelPoint(first, width: width, height: height))
                for point in annotation.points.dropFirst() {
                    context.addLine(to: pixelPoint(point, width: width, height: height))
                }
                context.strokePath()
            }
        case .text:
            if let point = annotation.points.first, let text = annotation.text {
                drawText(
                    text,
                    at: pixelPoint(point, width: width, height: height),
                    style: annotation.style,
                    context: context
                )
            }
        case .counter:
            if let point = annotation.points.first {
                drawCounter(
                    annotation.counter ?? 1,
                    at: pixelPoint(point, width: width, height: height),
                    style: annotation.style,
                    context: context
                )
            }
        case .blur, .pixelate:
            break
        }
        context.restoreGState()
    }

    private static func drawArrowHead(from start: CGPoint, to end: CGPoint, in context: CGContext, size: CGFloat) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let left = CGPoint(x: end.x - size * cos(angle - .pi / 6), y: end.y - size * sin(angle - .pi / 6))
        let right = CGPoint(x: end.x - size * cos(angle + .pi / 6), y: end.y - size * sin(angle + .pi / 6))
        context.move(to: end)
        context.addLine(to: left)
        context.move(to: end)
        context.addLine(to: right)
        context.strokePath()
    }

    private static func drawText(_ text: String, at point: CGPoint, style: AnnotationStyle, context: CGContext) {
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold),
            .foregroundColor: nsColor(style.color),
            .strokeColor: NSColor.white.withAlphaComponent(0.7),
            .strokeWidth: -1,
        ]
        NSAttributedString(string: text, attributes: attributes).draw(at: CGPoint(x: point.x, y: point.y - style.fontSize))
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawCounter(_ value: Int, at point: CGPoint, style: AnnotationStyle, context: CGContext) {
        let diameter = max(24, style.fontSize + 8)
        let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
        context.fillEllipse(in: rect)
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        let text = NSAttributedString(
            string: String(value),
            attributes: [
                .font: NSFont.systemFont(ofSize: style.fontSize * 0.72, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
        )
        let size = text.size()
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func pixelPoint(_ point: NormalizedPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: point.x * width, y: (1 - point.y) * height)
    }

    private static func pixelRect(_ rect: NormalizedRect, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: rect.x * width,
            y: (1 - rect.y - rect.height) * height,
            width: rect.width * width,
            height: rect.height * height
        )
    }

    private static func cgColor(_ color: RGBAColor) -> CGColor {
        CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    private static func nsColor(_ color: RGBAColor) -> NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}
