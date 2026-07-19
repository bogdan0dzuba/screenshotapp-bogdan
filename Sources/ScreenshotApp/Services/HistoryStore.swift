import AppKit
import Combine
import Foundation
import ScreenshotCore

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [CaptureItem] = []
    @Published private(set) var folderURL: URL

    private var maximumCount: Int
    private var maximumAgeDays: Int
    private let fileManager: FileManager

    init(
        folderURL: URL,
        maximumCount: Int,
        maximumAgeDays: Int,
        fileManager: FileManager = .default
    ) {
        self.folderURL = folderURL
        self.maximumCount = min(max(1, maximumCount), HistoryRetentionPolicy.maximumCaptures)
        self.maximumAgeDays = maximumAgeDays
        self.fileManager = fileManager
        try? reload()
    }

    func update(folderURL: URL, maximumCount: Int, maximumAgeDays: Int) throws {
        self.folderURL = folderURL
        self.maximumCount = min(max(1, maximumCount), HistoryRetentionPolicy.maximumCaptures)
        self.maximumAgeDays = maximumAgeDays
        try reload()
    }

    @discardableResult
    func importCapture(at sourceURL: URL, source: CaptureSource? = nil) throws -> CaptureItem {
        try ensureFolder()
        let id = UUID()
        let date = Date()
        let stem = Self.fileStem(date: date, id: id)
        let originalURL = folderURL.appendingPathComponent("\(stem).source.png")
        let imageURL = folderURL.appendingPathComponent("\(stem).png")
        let projectURL = folderURL.appendingPathComponent("\(stem).project.json")

        try fileManager.copyItem(at: sourceURL, to: originalURL)
        try fileManager.copyItem(at: sourceURL, to: imageURL)
        guard let image = NSImage(contentsOf: originalURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let document = EditorDocument(
            imageFileName: originalURL.lastPathComponent,
            canvasSize: CanvasSize(width: Double(cgImage.width), height: Double(cgImage.height)),
            annotations: [],
            captureSource: source
        )
        try writeProject(document, to: projectURL)
        let item = CaptureItem(
            id: id,
            createdAt: date,
            imageURL: imageURL,
            projectURL: projectURL,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            captureSource: source
        )
        items.insert(item, at: 0)
        try applyRetention(to: items)
        return item
    }

    @discardableResult
    func importImage(_ image: CGImage, source: CaptureSource? = nil) throws -> CaptureItem {
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotApp-\(UUID().uuidString).png")
        try Self.write(image, to: temporaryURL, format: .png)
        defer { try? fileManager.removeItem(at: temporaryURL) }
        return try importCapture(at: temporaryURL, source: source)
    }

    func loadDocument(for item: CaptureItem) -> EditorDocument {
        guard let projectURL = item.projectURL,
              let data = try? Data(contentsOf: projectURL),
              let document = try? JSONDecoder().decode(EditorDocument.self, from: data) else {
            return EditorDocument(
                imageFileName: item.imageURL.lastPathComponent,
                canvasSize: CanvasSize(width: Double(item.pixelWidth), height: Double(item.pixelHeight)),
                annotations: [],
                captureSource: item.captureSource
            )
        }
        return document
    }

    func sourceImageURL(for item: CaptureItem, document: EditorDocument? = nil) -> URL {
        let document = document ?? loadDocument(for: item)
        let candidate = folderURL.appendingPathComponent(document.imageFileName)
        return fileManager.fileExists(atPath: candidate.path) ? candidate : item.imageURL
    }

    func saveRendered(_ image: CGImage, document: EditorDocument, for item: CaptureItem) throws {
        try Self.write(image, to: item.imageURL, format: .png)
        if let projectURL = item.projectURL {
            try writeProject(document, to: projectURL)
        }
        objectWillChange.send()
    }

    func delete(_ item: CaptureItem) throws {
        try trashFiles(for: item)
        items.removeAll { $0.id == item.id }
    }

    func clearAll() throws {
        try ensureFolder()
        let files = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var firstError: Error?
        for url in files where CaptureFileClassifier.isRegularManagedCaptureFile(url) {
            do {
                try trash(url)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        items.removeAll { !fileManager.fileExists(atPath: $0.imageURL.path) }
        if let firstError { throw firstError }
        items.removeAll()
    }

    func reload() throws {
        try ensureFolder()
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .isRegularFileKey]
        let files = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        let captures = files.filter(CaptureFileClassifier.isRenderedCapture).compactMap { url -> CaptureItem? in
            guard let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let values = try? url.resourceValues(forKeys: keys)
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            let stem = url.deletingPathExtension().lastPathComponent
            let project = folderURL.appendingPathComponent("\(stem).project.json")
            let projectURL = CaptureFileClassifier.isRegularManagedCaptureFile(project) ? project : nil
            let document = projectURL.flatMap { url in
                (try? Data(contentsOf: url)).flatMap { data in
                    try? JSONDecoder().decode(EditorDocument.self, from: data)
                }
            }
            let idText = String(stem.suffix(36))
            let id = UUID(uuidString: idText) ?? Self.stableUUID(for: url.path)
            return CaptureItem(
                id: id,
                createdAt: date,
                imageURL: url,
                projectURL: projectURL,
                pixelWidth: cgImage.width,
                pixelHeight: cgImage.height,
                captureSource: document?.captureSource
            )
        }
        try applyRetention(to: captures)
    }

    static func write(_ image: CGImage, to url: URL, format: AppPreferences.ImageFormat) throws {
        let representation = NSBitmapImageRep(cgImage: image)
        let type: NSBitmapImageRep.FileType = format == .png ? .png : .jpeg
        let properties: [NSBitmapImageRep.PropertyKey: Any] = format == .jpeg ? [.compressionFactor: 0.92] : [:]
        guard let data = representation.representation(using: type, properties: properties) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }

    private func applyRetention(to candidates: [CaptureItem]) throws {
        let retained = HistoryIndex.pruned(
            items: candidates,
            maximumCount: maximumCount,
            maximumAgeDays: maximumAgeDays,
            now: Date()
        )
        let retainedIDs = Set(retained.map(\.id))
        let removed = candidates.filter { !retainedIDs.contains($0.id) }
        items = retained
        var firstError: Error?
        for item in removed {
            do {
                try trashFiles(for: item)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private func ensureFolder() throws {
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    private func writeProject(_ document: EditorDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
    }

    private func trashFiles(for item: CaptureItem) throws {
        let stem = item.imageURL.deletingPathExtension().lastPathComponent
        let urls = [
            item.imageURL,
            item.projectURL ?? folderURL.appendingPathComponent("\(stem).project.json"),
            folderURL.appendingPathComponent("\(stem).source.png"),
        ]
        var firstError: Error?
        for url in CaptureFileClassifier.regularManagedCaptureFiles(in: Array(Set(urls))) {
            do {
                try trash(url)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private func trash(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
    }

    private static func fileStem(date: Date, id: UUID) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Снимок \(formatter.string(from: date))-\(id.uuidString)"
    }

    private static func stableUUID(for string: String) -> UUID {
        var hash = Hasher()
        hash.combine(string)
        let value = UInt64(bitPattern: Int64(hash.finalize()))
        let suffix = String(format: "%012llx", value & 0xFFFFFFFFFFFF)
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)") ?? UUID()
    }
}
