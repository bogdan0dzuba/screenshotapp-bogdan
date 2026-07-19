public struct CaptureCompletionPolicy: Equatable, Sendable {
    public var opensEditor: Bool
    public var revealsShelf: Bool

    public init(opensEditor: Bool, revealsShelf: Bool) {
        self.opensEditor = opensEditor
        self.revealsShelf = revealsShelf
    }

    public static let standard = CaptureCompletionPolicy(opensEditor: true, revealsShelf: true)
}
