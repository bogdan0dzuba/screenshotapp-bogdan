import Foundation

public enum AsyncDeadlineError: Error, Equatable, Sendable {
    case timedOut
}

public enum AsyncDeadline {
    public static func value<Value: Sendable>(
        timeout: TimeInterval,
        start: @escaping @Sendable (
            @escaping @Sendable (Result<Value, Error>) -> Void
        ) -> Void
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let resolution = DeadlineResolution(continuation)
            start { result in resolution.resolve(result) }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                resolution.resolve(.failure(AsyncDeadlineError.timedOut))
            }
        }
    }
}

private final class DeadlineResolution<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
