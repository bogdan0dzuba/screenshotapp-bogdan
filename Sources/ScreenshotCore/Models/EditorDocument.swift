import Foundation

public struct EditorDocument: Codable, Equatable, Sendable {
    public var imageFileName: String
    public var canvasSize: CanvasSize
    public var annotations: [Annotation]
    public var captureSource: CaptureSource?

    public init(
        imageFileName: String,
        canvasSize: CanvasSize,
        annotations: [Annotation],
        captureSource: CaptureSource? = nil
    ) {
        self.imageFileName = imageFileName
        self.canvasSize = canvasSize
        self.annotations = annotations
        self.captureSource = captureSource
    }

    public static let empty = EditorDocument(
        imageFileName: "",
        canvasSize: CanvasSize(width: 0, height: 0),
        annotations: [],
        captureSource: nil
    )
}
