import Foundation

public struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = RGBAColor(red: 0.96, green: 0.22, blue: 0.27)
    public static let yellow = RGBAColor(red: 1, green: 0.78, blue: 0.12, alpha: 0.55)
    public static let blue = RGBAColor(red: 0.16, green: 0.52, blue: 0.96)
    public static let black = RGBAColor(red: 0.08, green: 0.08, blue: 0.1)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
}

public struct AnnotationStyle: Codable, Equatable, Sendable {
    public var color: RGBAColor
    public var lineWidth: Double
    public var fontSize: Double
    public var filled: Bool

    public init(color: RGBAColor, lineWidth: Double = 4, fontSize: Double = 24, filled: Bool = false) {
        self.color = color
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.filled = filled
    }
}

public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case arrow
    case line
    case rectangle
    case ellipse
    case pencil
    case highlighter
    case text
    case counter
    case blur
    case pixelate
}

public struct Annotation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: AnnotationKind
    public var points: [NormalizedPoint]
    public var rect: NormalizedRect?
    public var text: String?
    public var counter: Int?
    public var style: AnnotationStyle

    public init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        points: [NormalizedPoint] = [],
        rect: NormalizedRect? = nil,
        text: String? = nil,
        counter: Int? = nil,
        style: AnnotationStyle = .init(color: .red)
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.rect = rect
        self.text = text
        self.counter = counter
        self.style = style
    }

    public static func rectangle(_ rect: NormalizedRect, style: AnnotationStyle) -> Annotation {
        Annotation(kind: .rectangle, rect: rect, style: style)
    }

    public static func line(from: NormalizedPoint, to: NormalizedPoint, style: AnnotationStyle) -> Annotation {
        Annotation(kind: .line, points: [from, to], style: style)
    }
}
