import Foundation

public struct CaptureItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var imageURL: URL
    public var projectURL: URL?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var captureSource: CaptureSource?

    public init(
        id: UUID,
        createdAt: Date,
        imageURL: URL,
        projectURL: URL?,
        pixelWidth: Int,
        pixelHeight: Int,
        captureSource: CaptureSource? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.imageURL = imageURL
        self.projectURL = projectURL
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.captureSource = captureSource
    }
}
