import CoreGraphics

/// Deterministic LRU storage. Confine access to one actor or thread.
public struct DecodedImageCache<Key: Hashable> {
    private struct Entry {
        let image: CGImage
        let bytes: Int
    }

    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private let maximumBytes: Int
    private let maximumCount: Int
    public private(set) var residentBytes = 0
    public var count: Int { entries.count }

    public init(maximumBytes: Int = 128 * 1024 * 1024, maximumCount: Int = 48) {
        self.maximumBytes = max(0, maximumBytes)
        self.maximumCount = max(0, maximumCount)
    }

    public mutating func image(for key: Key) -> CGImage? {
        guard let entry = entries[key] else { return nil }
        touch(key)
        return entry.image
    }

    public mutating func insert(_ image: CGImage, for key: Key) {
        removeValue(for: key)
        let (bytes, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !overflow, bytes > 0, bytes <= maximumBytes, maximumCount > 0 else { return }
        while residentBytes > maximumBytes - bytes || count >= maximumCount {
            guard let oldest = order.first else { break }
            removeValue(for: oldest)
        }
        entries[key] = Entry(image: image, bytes: bytes)
        residentBytes += bytes
        touch(key)
    }

    public mutating func removeValue(for key: Key) {
        if let removed = entries.removeValue(forKey: key) { residentBytes -= removed.bytes }
        order.removeAll { $0 == key }
    }

    public mutating func removeAll(where predicate: (Key) -> Bool) {
        for key in order.filter(predicate) { removeValue(for: key) }
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
