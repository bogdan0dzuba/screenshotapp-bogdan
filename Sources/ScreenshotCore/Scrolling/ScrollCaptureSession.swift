import CoreGraphics

public enum ScrollCaptureDirection: Sendable {
    case down
    case up
}

public struct ScrollCaptureSession {
    public private(set) var frames: [CGImage]
    private var observations: [CGImage]
    private var additions: [ScrollCaptureDirection]

    public init(frames: [CGImage]) {
        self.frames = frames
        self.observations = frames
        self.additions = Array(repeating: .down, count: max(0, frames.count - 1))
    }

    public mutating func add(_ frame: CGImage) {
        add(frame, direction: .down)
    }

    public mutating func add(_ frame: CGImage, direction: ScrollCaptureDirection) {
        switch direction {
        case .down:
            frames.append(frame)
        case .up:
            frames.insert(frame, at: 0)
        }
        observations.append(frame)
        additions.append(direction)
    }

    public mutating func undoLastFrame() {
        guard observations.count > 1, let direction = additions.popLast() else { return }
        observations.removeLast()
        switch direction {
        case .down:
            frames.removeLast()
        case .up:
            frames.removeFirst()
        }
    }

    public var latestFrame: CGImage? { observations.last }

    public func finish() throws -> CGImage {
        try ScrollStitcher.stitch(frames)
    }
}
