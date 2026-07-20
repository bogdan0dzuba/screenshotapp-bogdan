import AppKit
import Combine
import Foundation
import ImageIO
import ScreenshotCore

private actor CaptureImageDecodeQueue {
    func decode(url: URL, maximumPixelSize: Int?) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        if let maximumPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }

        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}

private let captureImageDecodeQueue = CaptureImageDecodeQueue()

@MainActor
final class CaptureImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    private var requestState = ImageLoadRequestState()

    func load(url: URL, maximumPixelSize: Int?, revision: Int) async {
        let request = ImageLoadRequestKey(
            path: url.standardizedFileURL.path,
            maximumPixelSize: maximumPixelSize,
            revision: revision
        )
        let previousRequest = requestState.loadedRequest
        guard let token = requestState.begin(request) else { return }
        if previousRequest?.path != request.path || previousRequest?.revision != request.revision {
            image = nil
        }

        let decoded = await captureImageDecodeQueue.decode(
            url: url,
            maximumPixelSize: maximumPixelSize
        )
        guard !Task.isCancelled else {
            requestState.cancel(token)
            return
        }
        guard let decoded else {
            requestState.fail(token)
            return
        }
        guard requestState.finish(token, request: request) else { return }
        image = NSImage(
            cgImage: decoded,
            size: CGSize(width: decoded.width, height: decoded.height)
        )
    }
}
