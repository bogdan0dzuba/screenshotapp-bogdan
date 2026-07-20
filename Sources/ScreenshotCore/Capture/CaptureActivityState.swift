import Foundation

public struct CaptureActivityState: Equatable, Sendable {
    private enum ForegroundOperation: Equatable, Sendable {
        case idle
        case capture(UUID)
        case storageChange(UUID)
    }

    private var foregroundOperation: ForegroundOperation = .idle
    private var pendingImports: Set<UUID> = []

    public init() {}

    public var canStartCapture: Bool {
        foregroundOperation == .idle
    }

    public var canChangeStorage: Bool {
        foregroundOperation == .idle && pendingImports.isEmpty
    }

    public var canPresentCaptureResults: Bool {
        foregroundOperation == .idle
    }

    public var isCaptureActive: Bool {
        if case .capture = foregroundOperation { return true }
        return false
    }

    public var pendingImportCount: Int {
        pendingImports.count
    }

    @discardableResult
    public mutating func beginCapture(id: UUID) -> Bool {
        guard canStartCapture else { return false }
        foregroundOperation = .capture(id)
        return true
    }

    @discardableResult
    public mutating func finishCaptureAndBeginImport(id: UUID) -> Bool {
        guard foregroundOperation == .capture(id) else { return false }
        foregroundOperation = .idle
        pendingImports.insert(id)
        return true
    }

    @discardableResult
    public mutating func cancelCapture(id: UUID) -> Bool {
        guard foregroundOperation == .capture(id) else { return false }
        foregroundOperation = .idle
        return true
    }

    @discardableResult
    public mutating func finishImport(id: UUID) -> Bool {
        pendingImports.remove(id) != nil
    }

    @discardableResult
    public mutating func beginStorageChange(id: UUID) -> Bool {
        guard canChangeStorage else { return false }
        foregroundOperation = .storageChange(id)
        return true
    }

    @discardableResult
    public mutating func finishStorageChange(id: UUID) -> Bool {
        guard foregroundOperation == .storageChange(id) else { return false }
        foregroundOperation = .idle
        return true
    }
}
