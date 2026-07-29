import CoreGraphics

public enum ScrollCaptureDirection: Equatable, Sendable {
    case down
    case up
}

public struct ScrollCaptureSession {
    public private(set) var frames: [CGImage]
    public private(set) var stitchSeams: [ScrollStitchSeam?]
    private var observations: [CGImage]
    private var additions: [ScrollCaptureDirection]

    public var seamOverlaps: [Int?] {
        stitchSeams.map { $0?.overlap }
    }

    public init(frames: [CGImage]) {
        self.frames = frames
        self.stitchSeams = Array(repeating: nil, count: max(0, frames.count - 1))
        self.observations = frames
        self.additions = Array(repeating: .down, count: max(0, frames.count - 1))
    }

    public mutating func add(_ frame: CGImage) {
        add(frame, direction: .down)
    }

    public mutating func add(_ frame: CGImage, direction: ScrollCaptureDirection) {
        add(frame, direction: direction, overlap: nil)
    }

    public mutating func add(
        _ frame: CGImage,
        direction: ScrollCaptureDirection,
        overlap: Int
    ) {
        add(frame, direction: direction, overlap: Optional(overlap))
    }

    private mutating func add(
        _ frame: CGImage,
        direction: ScrollCaptureDirection,
        overlap: Int?
    ) {
        switch direction {
        case .down:
            frames.append(frame)
            stitchSeams.append(overlap.map { .append(overlap: $0) })
        case .up:
            frames.insert(frame, at: 0)
            stitchSeams.insert(overlap.map { .prepend(overlap: $0) }, at: 0)
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
            stitchSeams.removeLast()
        case .up:
            frames.removeFirst()
            stitchSeams.removeFirst()
        }
    }

    public var latestFrame: CGImage? { observations.last }

    public func finish() throws -> CGImage {
        let recordedSeams = stitchSeams.compactMap { $0 }
        if recordedSeams.count == stitchSeams.count {
            return try ScrollStitcher.stitch(frames, seams: recordedSeams)
        }
        return try ScrollStitcher.stitch(frames)
    }
}
