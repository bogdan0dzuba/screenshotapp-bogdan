import Foundation

/// Owns only the child launched for this capture. Cancellation never affects other apps.
public enum CaptureProcessRunner {
    public static func run(executableURL: URL, arguments: [String], outputURL: URL,
                           timeout: TimeInterval?) async throws -> Int32 {
        let execution = CaptureProcessExecution(outputURL: outputURL)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                execution.start(executableURL: executableURL, arguments: arguments,
                                timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            execution.abort(CancellationError())
        }
    }
}

private final class CaptureProcessExecution: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let outputURL: URL
    private var continuation: CheckedContinuation<Int32, Error>?
    private var abortError: Error?
    private var finished = false
    private var deadline: DispatchWorkItem?

    init(outputURL: URL) { self.outputURL = outputURL }

    func start(executableURL: URL, arguments: [String], timeout: TimeInterval?,
               continuation: CheckedContinuation<Int32, Error>) {
        lock.lock()
        if let abortError {
            lock.unlock()
            continuation.resume(throwing: abortError)
            return
        }
        self.continuation = continuation
        process.executableURL = executableURL
        process.arguments = arguments
        process.terminationHandler = { [self] process in complete(status: process.terminationStatus) }
        do {
            // Serialize cancellation with launch so an already-cancelled task cannot start a child.
            try process.run()
            if let timeout {
                let deadline = DispatchWorkItem { [weak self] in self?.abort(AsyncDeadlineError.timedOut) }
                self.deadline = deadline
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            }
            lock.unlock()
        } catch {
            self.continuation = nil
            finished = true
            process.terminationHandler = nil
            lock.unlock()
            continuation.resume(throwing: error)
        }
    }

    func abort(_ error: Error) {
        lock.lock()
        guard !finished, abortError == nil else { lock.unlock(); return }
        abortError = error
        deadline?.cancel()
        deadline = nil
        let pending = continuation
        continuation = nil
        if process.isRunning { process.terminate() }
        lock.unlock()
        pending?.resume(throwing: error)
    }

    private func complete(status: Int32) {
        lock.lock()
        finished = true
        deadline?.cancel()
        deadline = nil
        let pending = continuation
        continuation = nil
        let abandoned = abortError != nil
        process.terminationHandler = nil
        lock.unlock()
        // An OS helper may finish writing after its caller has stopped waiting.
        if abandoned { try? FileManager.default.removeItem(at: outputURL) }
        pending?.resume(returning: status)
    }
}
