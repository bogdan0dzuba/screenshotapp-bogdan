import Foundation

public enum AnnotationDraftBuilder {
    public static func make(
        kind: AnnotationKind,
        start: NormalizedPoint,
        end: NormalizedPoint,
        points: [NormalizedPoint],
        style: AnnotationStyle,
        text: String? = nil,
        counter: Int? = nil,
        minimumRectSize: Double = 0
    ) -> Annotation? {
        switch kind {
        case .arrow, .line:
            return Annotation(kind: kind, points: [start, end], style: style)
        case .rectangle, .ellipse, .blur, .pixelate:
            let rect = normalizedRect(from: start, to: end)
            guard rect.width > minimumRectSize, rect.height > minimumRectSize else { return nil }
            return Annotation(kind: kind, rect: rect, style: style)
        case .pencil, .highlighter:
            return Annotation(
                kind: kind,
                points: points.isEmpty ? [start, end] : points,
                style: style
            )
        case .text:
            return Annotation(kind: .text, points: [end], text: text, style: style)
        case .counter:
            return Annotation(kind: .counter, points: [end], counter: counter, style: style)
        }
    }

    private static func normalizedRect(
        from start: NormalizedPoint,
        to end: NormalizedPoint
    ) -> NormalizedRect {
        NormalizedRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }
}
