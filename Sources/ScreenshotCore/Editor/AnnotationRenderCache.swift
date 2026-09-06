import CoreGraphics

/// Keeps only the current preview for a single immutable source image.
public struct AnnotationRenderCache {
    private let baseImage: CGImage
    private var document: EditorDocument?
    private var renderedImage: CGImage?

    public init(baseImage: CGImage) {
        self.baseImage = baseImage
    }

    public mutating func image(for document: EditorDocument) throws -> CGImage {
        if self.document == document, let renderedImage { return renderedImage }
        let image = try AnnotationRenderer.render(baseImage: baseImage, document: document)
        self.document = document
        renderedImage = image
        return image
    }
}
