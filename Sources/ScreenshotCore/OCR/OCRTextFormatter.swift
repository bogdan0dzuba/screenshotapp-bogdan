import Foundation

public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    public var minX: Double
    public var midY: Double

    public init(text: String, minX: Double, midY: Double) {
        self.text = text
        self.minX = minX
        self.midY = midY
    }
}

public enum OCRTextFormatter {
    public static func join(lines: [RecognizedLine]) -> String {
        lines
            .sorted { lhs, rhs in
                if abs(lhs.midY - rhs.midY) < 0.015 {
                    return lhs.minX < rhs.minX
                }
                return lhs.midY > rhs.midY
            }
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }
}
