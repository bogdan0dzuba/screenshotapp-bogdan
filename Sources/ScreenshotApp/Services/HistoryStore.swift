import AppKit
import Combine
import Foundation
import ImageIO
import ScreenshotCore
import UniformTypeIdentifiers

private enum HistoryStoreError: LocalizedError {
    case captureFolderChanged

    var errorDescription: String? {
        "Папка снимков изменилась во время сохранения. Повторите захват."
    }
}

private actor CapturePreparationQueue {
    func prepareCapture(
        at sourceURL: URL,
        folderURL: URL,
        source: CaptureSource?,
        capturedAt: Date
    ) throws -> CaptureItem {
        try HistoryStore.prepareCapture(
            at: sourceURL,
            folderURL: folderURL,
            source: source,
            capturedAt: capturedAt
        )
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [CaptureItem] = []
    @Published private(set) var folderURL: URL
    @Published private(set) var imageRevision = 0

    private var maximumCount: Int
    private var maximumAgeDays: Int
    private var automaticCleanupEnabled: Bool
    private let fileManager: FileManager
    private let preparationQueue = CapturePreparationQueue()

    init(
        folderURL: URL,
        maximumCount: Int,
        maximumAgeDays: Int,
        automaticCleanupEnabled: Bool,
        fileManager: FileManager = .default
    ) {
        self.folderURL = folderURL
        self.maximumCount = min(max(1, maximumCount), HistoryRetentionPolicy.maximumCaptures)
        self.maximumAgeDays = maximumAgeDays
        self.automaticCleanupEnabled = automaticCleanupEnabled
        self.fileManager = fileManager
    }

    func update(
        folderURL: URL,
        maximumCount: Int,
        maximumAgeDays: Int,
        automaticCleanupEnabled: Bool
    ) throws {
        self.folderURL = folderURL
        self.maximumCount = min(max(1, maximumCount), HistoryRetentionPolicy.maximumCaptures)
        self.maximumAgeDays = maximumAgeDays
        self.automaticCleanupEnabled = automaticCleanupEnabled
        try reload()
    }

    @discardableResult
    func importCapture(
        at sourceURL: URL,
        source: CaptureSource? = nil,
        capturedAt: Date = Date()
    ) async throws -> CaptureItem {
        let targetFolder = folderURL
        let item = try await preparationQueue.prepareCapture(
            at: sourceURL,
            folderURL: targetFolder,
            source: source,
            capturedAt: capturedAt
        )
        return try acceptImported(item, targetFolder: targetFolder)
    }

    @discardableResult
    func importImage(
        _ image: CGImage,
        source: CaptureSource? = nil,
        capturedAt: Date = Date()
    ) async throws -> CaptureItem {
        let targetFolder = folderURL
        let temporaryURL = try await Task.detached(priority: .userInitiated) {
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ScreenshotApp-\(UUID().uuidString).png")
            try Self.writePNG(image, to: temporaryURL)
            return temporaryURL
        }.value
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let item = try await preparationQueue.prepareCapture(
            at: temporaryURL,
            folderURL: targetFolder,
            source: source,
            capturedAt: capturedAt
        )
        return try acceptImported(item, targetFolder: targetFolder)
    }

    private func acceptImported(_ item: CaptureItem, targetFolder: URL) throws -> CaptureItem {
        guard targetFolder == folderURL else { throw HistoryStoreError.captureFolderChanged }
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        try applyRetention(to: items)
        imageRevision &+= 1
        return item
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
        let candidate = item.imageURL
            .deletingLastPathComponent()
            .appendingPathComponent(document.imageFileName)
        return fileManager.fileExists(atPath: candidate.path) ? candidate : item.imageURL
    }

    func saveRendered(_ image: CGImage, document: EditorDocument, for item: CaptureItem) throws {
        try Self.write(image, to: item.imageURL, format: .png)
        if let projectURL = item.projectURL {
            try writeProject(document, to: projectURL)
        }
        imageRevision &+= 1
    }

    func delete(_ item: CaptureItem) throws {
        try trashFiles(for: item)
        items.removeAll { $0.id == item.id }
        imageRevision &+= 1
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
        imageRevision &+= 1
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
            guard let dimensions = ImageFileMetadata.dimensions(at: url) else { return nil }
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
                pixelWidth: dimensions.width,
                pixelHeight: dimensions.height,
                captureSource: document?.captureSource
            )
        }
        try applyRetention(to: captures)
        imageRevision &+= 1
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
            automaticCleanupEnabled: automaticCleanupEnabled,
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

    nonisolated fileprivate static func prepareCapture(
        at sourceURL: URL,
        folderURL: URL,
        source: CaptureSource?,
        capturedAt: Date
    ) throws -> CaptureItem {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let id = UUID()
        let date = capturedAt
        let baseStem = CaptureFileName.baseStem(
            for: date,
            applicationName: source?.applicationName
        )
        let occupiedStems = occupiedCaptureStems(in: folderURL, fileManager: fileManager)
        let stem = CaptureFileName.availableStem(baseStem: baseStem, occupiedStems: occupiedStems)
        let originalURL = folderURL.appendingPathComponent("\(stem).source.png")
        let imageURL = folderURL.appendingPathComponent("\(stem).png")
        let projectURL = folderURL.appendingPathComponent("\(stem).project.json")
        var createdURLs: [URL] = []
        do {
            try fileManager.copyItem(at: sourceURL, to: originalURL)
            createdURLs.append(originalURL)
            try fileManager.copyItem(at: sourceURL, to: imageURL)
            createdURLs.append(imageURL)
            guard let dimensions = ImageFileMetadata.dimensions(at: originalURL) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let document = EditorDocument(
                imageFileName: originalURL.lastPathComponent,
                canvasSize: CanvasSize(width: Double(dimensions.width), height: Double(dimensions.height)),
                annotations: [],
                captureSource: source
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            createdURLs.append(projectURL)
            try encoder.encode(document).write(to: projectURL, options: .atomic)
            return CaptureItem(
                id: id,
                createdAt: date,
                imageURL: imageURL,
                projectURL: projectURL,
                pixelWidth: dimensions.width,
                pixelHeight: dimensions.height,
                captureSource: source
            )
        } catch {
            for url in createdURLs.reversed() {
                try? fileManager.removeItem(at: url)
            }
            throw error
        }
    }

    nonisolated private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func trashFiles(for item: CaptureItem) throws {
        let stem = item.imageURL.deletingPathExtension().lastPathComponent
        let itemFolder = item.imageURL.deletingLastPathComponent()
        let urls = [
            item.imageURL,
            item.projectURL ?? itemFolder.appendingPathComponent("\(stem).project.json"),
            itemFolder.appendingPathComponent("\(stem).source.png"),
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

    nonisolated private static func occupiedCaptureStems(
        in folderURL: URL,
        fileManager: FileManager
    ) -> Set<String> {
        let names = (try? fileManager.contentsOfDirectory(atPath: folderURL.path)) ?? []
        return Set(names.compactMap { name in
            for suffix in [".source.png", ".project.json", ".png"] where name.hasSuffix(suffix) {
                return String(name.dropLast(suffix.count))
            }
            return nil
        })
    }

    nonisolated private static func stableUUID(for string: String) -> UUID {
        var hash = Hasher()
        hash.combine(string)
        let value = UInt64(bitPattern: Int64(hash.finalize()))
        let suffix = String(format: "%012llx", value & 0xFFFFFFFFFFFF)
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)") ?? UUID()
    }
}
