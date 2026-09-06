import AppKit
import Foundation
import UniformTypeIdentifiers

public enum ScreenshotTransferError: LocalizedError {
    case unreadableImage
    case pasteboardRejectedData

    public var errorDescription: String? {
        switch self {
        case .unreadableImage: "Не удалось прочитать снимок"
        case .pasteboardRejectedData: "Не удалось поместить снимок в буфер обмена"
        }
    }
}

public enum ScreenshotTransfer {
    public static func pasteboardItem(for url: URL) -> NSPasteboardItem? {
        guard let pngData = try? Data(contentsOf: url),
              let image = NSImage(data: pngData),
              let tiffData = image.tiffRepresentation else {
            return nil
        }

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        item.setData(tiffData, forType: .tiff)
        item.setString(url.absoluteString, forType: .fileURL)
        return item
    }

    public static func writeImage(at url: URL, to pasteboard: NSPasteboard) throws {
        let pngData = try Data(contentsOf: url)
        guard let image = NSImage(data: pngData),
              let tiffData = image.tiffRepresentation else {
            throw ScreenshotTransferError.unreadableImage
        }

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        item.setData(tiffData, forType: .tiff)
        item.setString(url.absoluteString, forType: .fileURL)

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw ScreenshotTransferError.pasteboardRejectedData
        }
    }

    public static func itemProvider(for url: URL) -> NSItemProvider {
        let contentType = UTType(filenameExtension: url.pathExtension) ?? .png
        let provider: NSItemProvider
        if let data = try? Data(contentsOf: url) {
            provider = NSItemProvider(item: data as NSData, typeIdentifier: contentType.identifier)
        } else {
            provider = NSItemProvider()
        }
        provider.suggestedName = url.lastPathComponent
        provider.registerFileRepresentation(
            forTypeIdentifier: contentType.identifier,
            fileOptions: [.openInPlace],
            visibility: .all
        ) { completion in
            completion(url, true, nil)
            return nil
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all
        ) { completion in
            completion(url.absoluteString.data(using: .utf8), nil)
            return nil
        }
        return provider
    }
}
