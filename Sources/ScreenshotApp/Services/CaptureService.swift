import AppKit
import Foundation
import ImageIO
import ScreenCaptureKit
import ScreenshotCore
import UniformTypeIdentifiers

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

struct CaptureService: Sendable {
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
        if #available(macOS 15.2, *) {
            do {
                try? FileManager.default.removeItem(at: outputURL)
                let image = try await SCScreenshotManager.captureImage(in: integral)
                try Self.writePNG(image, to: outputURL)
                CaptureTelemetry.logger.info("native_region_capture_finished")
                return
            } catch {
                CaptureTelemetry.logger.notice("native_region_capture_fallback")
            }
        }
        let region = "\(Int(integral.minX)),\(Int(integral.minY)),\(Int(integral.width)),\(Int(integral.height))"
        try await runScreencapture(arguments: ["-x", "-R", region, outputURL.path], outputURL: outputURL)
    }

    private static func writePNG(_ image: CGImage, to outputURL: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.missingOutput
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.missingOutput
        }
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
                CaptureTelemetry.logger.info("capture_process_started")
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
