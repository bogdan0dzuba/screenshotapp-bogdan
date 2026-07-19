import AppKit
import Foundation
import ScreenshotCore

enum CaptureMode {
    case area
    case window
    case fullScreen
}

enum CaptureError: LocalizedError {
    case cancelled
    case failed(Int32)
    case missingOutput

    var errorDescription: String? {
        switch self {
        case .cancelled: "Захват отменен"
        case let .failed(code): "Не удалось сделать снимок (код \(code))"
        case .missingOutput: "Снимок не был создан"
        }
    }
}

final class CaptureService {
    func capture(_ mode: CaptureMode, to outputURL: URL) async throws {
        var arguments = ["-x"]
        switch mode {
        case .area: arguments += ["-i", "-s"]
        case .window: arguments += ["-i", "-w"]
        case .fullScreen: break
        }
        arguments.append(outputURL.path)
        try await runScreencapture(arguments: arguments, outputURL: outputURL)
    }

    func capture(rect: CGRect, to outputURL: URL) async throws {
        let integral = rect.integral
        let region = "\(Int(integral.minX)),\(Int(integral.minY)),\(Int(integral.width)),\(Int(integral.height))"
        try await runScreencapture(arguments: ["-x", "-R", region, outputURL.path], outputURL: outputURL)
    }

    private func runScreencapture(arguments: [String], outputURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            process.terminationHandler = { process in
                let outcome = CaptureProcessOutcome.resolve(
                    terminationStatus: process.terminationStatus,
                    outputExists: FileManager.default.fileExists(atPath: outputURL.path)
                )
                switch outcome {
                case .success:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CaptureError.cancelled)
                case let .failed(code):
                    continuation.resume(throwing: CaptureError.failed(code))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
