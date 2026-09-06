import CoreImage
import Foundation
@preconcurrency import ScreenCaptureKit
import ScreenshotCore

/// SCScreenshotManager can reject picker-only grants with -3801. SCStream consumes
/// the picker session grant directly. Capture one complete frame, then stop it.
final class SelectedContentFrameCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var completion: (@Sendable (Result<CGImage, Error>) -> Void)?
    private var finished = false

    static func image(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        let receiver = SelectedContentFrameCapture()
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        let stream = SCStream(filter: filter, configuration: configuration, delegate: receiver)
        try stream.addStreamOutput(receiver, type: .screen,
                                   sampleHandlerQueue: DispatchQueue(label: "ScreenshotApp.SelectedFrame"))
        let result: Result<CGImage, Error>
        do {
            let image = try await withTaskCancellationHandler {
                try await AsyncDeadline.value(timeout: 8) { completion in
                    receiver.register(completion)
                    guard !receiver.isFinished else { return }
                    stream.startCapture { error in
                        if let error { receiver.resolve(.failure(error)) }
                        // A late start after cancellation/timeout must not leave an orphan stream.
                        if receiver.isFinished { stream.stopCapture { _ in } }
                    }
                }
            } onCancel: {
                receiver.resolve(.failure(CaptureError.cancelled))
            }
            result = .success(image)
        } catch {
            result = .failure(error)
        }
        receiver.resolve(.failure(CaptureError.cancelled))
        // Bound cleanup too, and do not replace the actual capture error with a stop error.
        let _: Void? = try? await AsyncDeadline.value(timeout: 2) { completion in
            stream.stopCapture { _ in completion(.success(())) }
        }
        if Task.isCancelled { throw CaptureError.cancelled }
        return try result.get()
    }

    private func register(_ callback: @escaping @Sendable (Result<CGImage, Error>) -> Void) {
        lock.lock()
        if finished {
            lock.unlock()
            callback(.failure(CaptureError.cancelled))
        } else {
            completion = callback
            lock.unlock()
        }
    }

    private var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    private func resolve(_ result: Result<CGImage, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(result)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        resolve(.failure(error))
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !isFinished, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        let input = CIImage(cvPixelBuffer: buffer)
        guard let image = Self.imageContext.createCGImage(input, from: input.extent) else {
            resolve(.failure(CaptureError.missingOutput))
            return
        }
        resolve(.success(image))
    }
}
