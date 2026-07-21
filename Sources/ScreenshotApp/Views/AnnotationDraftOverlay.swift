import ScreenshotCore
import SwiftUI

struct AnnotationDraftOverlay: View {
    let annotation: Annotation
    let imageSize: CGSize

    var body: some View {
        Canvas { context, size in
            draw(annotation, in: &context, size: size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(
        _ annotation: Annotation,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let color = Color(annotation.style.color)
        let lineWidth = scaled(annotation.style.lineWidth, canvasWidth: size.width)
        let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

        switch annotation.kind {
        case .arrow, .line:
            guard annotation.points.count >= 2 else { return }
            let start = point(annotation.points[0], in: size)
            let end = point(annotation.points[1], in: size)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), style: stroke)
            if annotation.kind == .arrow {
                drawArrowHead(
                    from: start,
                    to: end,
                    color: color,
                    lineWidth: lineWidth,
                    context: &context
                )
            }
        case .rectangle, .blur, .pixelate:
            guard let normalized = annotation.rect else { return }
            let rect = rect(normalized, in: size)
            if annotation.kind == .blur || annotation.kind == .pixelate {
                context.fill(Path(rect), with: .color(color.opacity(0.12)))
                context.stroke(
                    Path(rect),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: max(1, lineWidth), dash: [6, 4])
                )
            } else {
                context.stroke(Path(rect), with: .color(color), style: stroke)
            }
        case .ellipse:
            guard let normalized = annotation.rect else { return }
            context.stroke(Path(ellipseIn: rect(normalized, in: size)), with: .color(color), style: stroke)
        case .pencil, .highlighter:
            guard let first = annotation.points.first else { return }
            var path = Path()
            path.move(to: point(first, in: size))
            for value in annotation.points.dropFirst() {
                path.addLine(to: point(value, in: size))
            }
            let freehandWidth = annotation.kind == .highlighter
                ? max(scaled(12, canvasWidth: size.width), lineWidth * 3)
                : lineWidth
            context.stroke(
                path,
                with: .color(color.opacity(annotation.kind == .highlighter ? 0.45 : 1)),
                style: StrokeStyle(lineWidth: freehandWidth, lineCap: .round, lineJoin: .round)
            )
        case .text:
            guard let anchor = annotation.points.first, let text = annotation.text else { return }
            context.draw(
                Text(text)
                    .font(.system(size: scaled(annotation.style.fontSize, canvasWidth: size.width), weight: .semibold))
                    .foregroundStyle(color),
                at: point(anchor, in: size),
                anchor: .topLeading
            )
        case .counter:
            guard let anchor = annotation.points.first else { return }
            let center = point(anchor, in: size)
            let diameter = max(
                scaled(24, canvasWidth: size.width),
                scaled(annotation.style.fontSize + 8, canvasWidth: size.width)
            )
            let circle = CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.fill(Path(ellipseIn: circle), with: .color(color))
            context.draw(
                Text(String(annotation.counter ?? 1))
                    .font(.system(size: diameter * 0.55, weight: .bold))
                    .foregroundStyle(.white),
                at: center
            )
        }
    }

    private func drawArrowHead(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        lineWidth: CGFloat,
        context: inout GraphicsContext
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let size = max(12, lineWidth * 4)
        let left = CGPoint(
            x: end.x - size * cos(angle - .pi / 6),
            y: end.y - size * sin(angle - .pi / 6)
        )
        let right = CGPoint(
            x: end.x - size * cos(angle + .pi / 6),
            y: end.y - size * sin(angle + .pi / 6)
        )
        var path = Path()
        path.move(to: left)
        path.addLine(to: end)
        path.addLine(to: right)
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func point(_ value: NormalizedPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: value.x * size.width, y: value.y * size.height)
    }

    private func rect(_ value: NormalizedRect, in size: CGSize) -> CGRect {
        CGRect(
            x: value.x * size.width,
            y: value.y * size.height,
            width: value.width * size.width,
            height: value.height * size.height
        )
    }

    private func scaled(_ value: Double, canvasWidth: CGFloat) -> CGFloat {
        max(1, CGFloat(value) * canvasWidth / max(imageSize.width, 1))
    }
}
