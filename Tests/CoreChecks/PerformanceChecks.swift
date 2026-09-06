import CoreGraphics
import Foundation
import ScreenshotCore

private func requirePerformance(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "PerformanceChecks: \(message)", code: 1) }
}

private func fixtureImage(width: Int = 512, height: Int = 512) throws -> CGImage {
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "fixture context", code: 1)
    }
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

func checkDecodedImageCache() throws {
    let image = try fixtureImage()
    let cost = image.bytesPerRow * image.height
    var cache = DecodedImageCache<String>(maximumBytes: cost * 2, maximumCount: 3)
    cache.insert(image, for: "a")
    cache.insert(image, for: "b")
    _ = cache.image(for: "a")
    cache.insert(image, for: "c")
    try requirePerformance(cache.image(for: "b") == nil, "evict least recently used by bytes")
    try requirePerformance(cache.image(for: "a") === image, "retain recently accessed image")
    try requirePerformance(cache.residentBytes == cost * 2, "byte accounting after eviction")
    cache.insert(image, for: "a")
    try requirePerformance(cache.residentBytes == cost * 2, "replacement must not double count")
    cache.removeValue(for: "a")
    try requirePerformance(cache.residentBytes == cost, "removal releases accounted bytes")
    cache.insert(try fixtureImage(width: 1024, height: 1024), for: "oversized")
    try requirePerformance(cache.image(for: "oversized") == nil, "oversized image must not be retained")
    try requirePerformance(cache.image(for: "c") === image, "oversized image must not flush useful cache")
    cache.insert(image, for: "old-revision")
    cache.removeAll { $0 == "old-revision" }
    try requirePerformance(cache.image(for: "old-revision") == nil, "obsolete revision must be evicted")
    var countLimited = DecodedImageCache<Int>(maximumBytes: cost * 10, maximumCount: 2)
    for key in 0..<3 { countLimited.insert(image, for: key) }
    try requirePerformance(countLimited.count == 2 && countLimited.image(for: 0) == nil,
                           "entry count remains bounded for small previews")
    var disabled = DecodedImageCache<Int>(maximumBytes: 0, maximumCount: 0)
    disabled.insert(image, for: 0)
    try requirePerformance(disabled.count == 0, "zero budget retains nothing")
}

func checkAnnotationRenderReuse() throws {
    let base = try fixtureImage()
    var document = EditorDocument(imageFileName: "fixture.png",
                                  canvasSize: CanvasSize(width: 512, height: 512), annotations: [])
    let plain = try AnnotationRenderer.render(baseImage: base, document: document)
    try requirePerformance(plain === base, "empty document must reuse original pixels")
    var cache = AnnotationRenderCache(baseImage: base)
    document.annotations = [.rectangle(NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
                                       style: .init(color: .red, lineWidth: 5))]
    let first = try cache.image(for: document)
    let again = try cache.image(for: document)
    try requirePerformance(first === again, "saving same preview must not render it again")
    document.annotations.removeAll()
    let cleared = try cache.image(for: document)
    try requirePerformance(cleared === base, "undo or clear must not return stale annotations")
    document.annotations = [.rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
                                       style: .init(color: .red, lineWidth: 5))]
    let changed = try cache.image(for: document)
    try requirePerformance(changed !== first && changed !== base, "changed document invalidates preview")
}

func runPerformanceStressChecks() throws {
    let start = CFAbsoluteTimeGetCurrent()
    var cache = DecodedImageCache<Int>()
    var peak = 0
    for index in 0..<2000 {
        try autoreleasepool {
            let image = try fixtureImage(width: 1024, height: 1024)
            cache.insert(image, for: index)
            peak = max(peak, cache.residentBytes)
            try requirePerformance(cache.residentBytes <= 128 * 1024 * 1024, "stress memory budget exceeded")
            try requirePerformance(cache.image(for: index) === image, "newest image remains available")
        }
    }
    print("Stress: 2000 image insertions, peak cache bytes=\(peak), seconds=\(CFAbsoluteTimeGetCurrent() - start)")
    let base = try fixtureImage(width: 3840, height: 2160)
    let document = EditorDocument(imageFileName: "4k.png", canvasSize: CanvasSize(width: 3840, height: 2160),
                                  annotations: [.rectangle(NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
                                                           style: .init(color: .red, lineWidth: 5))])
    var renderCache = AnnotationRenderCache(baseImage: base)
    let rendered = try renderCache.image(for: document)
    let cachedStart = CFAbsoluteTimeGetCurrent()
    for _ in 0..<1000 {
        let next = try renderCache.image(for: document)
        try requirePerformance(next === rendered, "4K preview unexpectedly rerendered")
    }
    let cachedSeconds = CFAbsoluteTimeGetCurrent() - cachedStart
    let uncachedStart = CFAbsoluteTimeGetCurrent()
    for _ in 0..<100 {
        try autoreleasepool { _ = try AnnotationRenderer.render(baseImage: base, document: document) }
    }
    print("Stress: 4K cached render 1000 calls=\(cachedSeconds)s; uncached 100 calls=\(CFAbsoluteTimeGetCurrent() - uncachedStart)s")
}
