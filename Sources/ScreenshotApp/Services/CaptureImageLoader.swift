import AppKit
import Combine
import Foundation
import ImageIO
import ScreenshotCore

private struct CaptureImageCacheKey: Hashable, Sendable {
    let path: String
    let maximumPixelSize: Int?
    let revision: Int
}

private actor CaptureImageDecodeQueue {
    private var cached = DecodedImageCache<CaptureImageCacheKey>()

    func decode(url: URL, maximumPixelSize: Int?, revision: Int) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let key = CaptureImageCacheKey(
            path: url.standardizedFileURL.path,
            maximumPixelSize: maximumPixelSize,
            revision: revision
        )
        if let cachedImage = cached.image(for: key) {
            return cachedImage
        }
        cached.removeAll { $0.path == key.path && $0.revision != revision }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let decoded: CGImage?
        if let maximumPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            decoded = CGImageSourceCreateImageAtIndex(source, 0, options)
        }

        guard !Task.isCancelled, let decoded else { return nil }
        cached.insert(decoded, for: key)
        return decoded
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
            maximumPixelSize: maximumPixelSize,
            revision: revision
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
