import Foundation

public enum AsyncDeadlineError: LocalizedError, Equatable, Sendable {
    case timedOut

    public var errorDescription: String? {
        "macOS не ответила вовремя при подготовке снимка. Повторите захват; если ошибка повторяется, проверьте разрешение «Запись экрана»."
    }
}

public enum AsyncDeadline {
    public static func value<Value: Sendable>(
        timeout: TimeInterval,
        start: @escaping @Sendable (
            @escaping @Sendable (Result<Value, Error>) -> Void
        ) -> Void
    ) async throws -> Value {
        let resolution = DeadlineResolution<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard resolution.register(continuation) else { return }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                    resolution.resolve(.failure(AsyncDeadlineError.timedOut))
                }
                start { result in resolution.resolve(result) }
            }
        } onCancel: {
            resolution.resolve(.failure(CancellationError()))
        }
    }
}

private final class DeadlineResolution<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?

    func register(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
