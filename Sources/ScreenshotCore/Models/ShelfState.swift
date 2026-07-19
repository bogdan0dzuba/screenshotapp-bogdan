import Foundation

public enum ShelfState: Codable, Equatable, Sendable {
    case expanded
    case collapsed
    case temporarilyHidden(until: Date)
    case hiddenUntilNextCapture

    public mutating func receivedNewCapture() {
        switch self {
        case .expanded, .collapsed:
            break
        case .temporarilyHidden, .hiddenUntilNextCapture:
            self = .collapsed
        }
    }

    public mutating func collapse() {
        self = .collapsed
    }

    public mutating func expand() {
        self = .expanded
    }

    public func isVisible(at date: Date = Date()) -> Bool {
        switch self {
        case .expanded, .collapsed:
            true
        case let .temporarilyHidden(until):
            date >= until
        case .hiddenUntilNextCapture:
            false
        }
    }
}
