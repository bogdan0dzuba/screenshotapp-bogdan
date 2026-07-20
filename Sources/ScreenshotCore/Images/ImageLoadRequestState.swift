import Foundation

public struct ImageLoadRequestKey: Equatable, Hashable, Sendable {
    public var path: String
    public var maximumPixelSize: Int?
    public var revision: Int

    public init(path: String, maximumPixelSize: Int?, revision: Int) {
        self.path = path
        self.maximumPixelSize = maximumPixelSize
        self.revision = revision
    }
}

public struct ImageLoadToken: Equatable, Hashable, Sendable {
    fileprivate var generation: UInt64
}

public struct ImageLoadRequestState: Equatable, Sendable {
    private struct ActiveRequest: Equatable, Sendable {
        var key: ImageLoadRequestKey
        var token: ImageLoadToken
    }

    private var generation: UInt64 = 0
    private var activeRequest: ActiveRequest?
    public private(set) var loadedRequest: ImageLoadRequestKey?

    public init() {}

    public mutating func begin(_ request: ImageLoadRequestKey) -> ImageLoadToken? {
        guard loadedRequest != request else { return nil }
        generation &+= 1
        let token = ImageLoadToken(generation: generation)
        activeRequest = ActiveRequest(key: request, token: token)
        loadedRequest = nil
        return token
    }

    @discardableResult
    public mutating func finish(_ token: ImageLoadToken, request: ImageLoadRequestKey) -> Bool {
        guard activeRequest == ActiveRequest(key: request, token: token) else { return false }
        activeRequest = nil
        loadedRequest = request
        return true
    }

    @discardableResult
    public mutating func fail(_ token: ImageLoadToken) -> Bool {
        guard activeRequest?.token == token else { return false }
        activeRequest = nil
        return true
    }

    @discardableResult
    public mutating func cancel(_ token: ImageLoadToken) -> Bool {
        fail(token)
    }
}
