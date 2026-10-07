import Foundation
import ScreenshotCore

private actor StartSignal {
    var signalled = false
    func mark() { signalled = true }
    private var completion: (@Sendable (Result<Int, Error>) -> Void)?
    func store(_ completion: @escaping @Sendable (Result<Int, Error>) -> Void) {
        self.completion = completion
    }
    func completeLate() { completion?(.success(1)) }
}

@main
struct ReliabilityChecks {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }

    static func main() async throws {
        let immediate: Int = try await AsyncDeadline.value(timeout: 0.1) { done in
            done(.success(7))
            done(.success(9)) // Duplicate callbacks must not resume twice.
        }
        try require(immediate == 7, "first completion wins")
        let lateCompletion = StartSignal()
        do {
            let _: Int = try await AsyncDeadline.value(timeout: 0.02) { done in
                Task { await lateCompletion.store(done) }
            }
            throw NSError(domain: "missing timeout", code: 1)
        } catch AsyncDeadlineError.timedOut { }
        await lateCompletion.completeLate() // A callback after timeout must not resume again.
        let started = StartSignal()
        let waiting = Task {
            let _: Int = try await AsyncDeadline.value(timeout: 30) { _ in Task { await started.mark() } }
        }
        while !(await started.signalled) { try await Task.sleep(nanoseconds: 1_000_000) }
        let cancelTime = Date()
        waiting.cancel()
        do { try await waiting.value; throw NSError(domain: "missing cancellation", code: 1) }
        catch is CancellationError { }
        try require(Date().timeIntervalSince(cancelTime) < 1, "cancellation must not wait for deadline")
        let preCancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let _: Int = try await AsyncDeadline.value(timeout: 30) { _ in
                fatalError("pre-cancelled operation must not start")
            }
        }
        do { try await preCancelled.value; throw NSError(domain: "missing pre-cancellation", code: 1) }
        catch is CancellationError { }

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Reliability-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: output) }
        let status = try await CaptureProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                                                       arguments: [], outputURL: output, timeout: 1)
        try require(status == 0, "child success")
        do {
            _ = try await CaptureProcessRunner.run(executableURL: URL(fileURLWithPath: "/missing/reliability-test"),
                                                  arguments: [], outputURL: output, timeout: 1)
            throw NSError(domain: "missing launch error", code: 1)
        } catch let error as NSError where error.domain != "missing launch error" { }
        try Data("partial capture".utf8).write(to: output)
        do {
            _ = try await CaptureProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/sleep"),
                                                  arguments: ["5"], outputURL: output, timeout: 0.05)
            throw NSError(domain: "missing process timeout", code: 1)
        } catch AsyncDeadlineError.timedOut { }
        let cleanupDeadline = Date().addingTimeInterval(1)
        while FileManager.default.fileExists(atPath: output.path), Date() < cleanupDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try require(!FileManager.default.fileExists(atPath: output.path), "abandoned child output must be removed")
        let processTask = Task {
            try await CaptureProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/sleep"),
                                               arguments: ["5"], outputURL: output, timeout: nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        processTask.cancel()
        do { _ = try await processTask.value; throw NSError(domain: "missing child cancellation", code: 1) }
        catch is CancellationError { }
        try await Task.sleep(nanoseconds: 100_000_000) // Deliver late and duplicate completion callbacks.
        print("ReliabilityChecks: OK (deadline, cancellation, child success/failure/timeout)")
    }
}
