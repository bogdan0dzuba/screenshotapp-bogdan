import Foundation

public enum HistoryRetentionPolicy {
    public static let maximumCaptures = 20
}

public enum CaptureFileClassifier {
    private static let stemPattern = #"^Снимок \d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.\d{2}-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#

    public static func isRenderedCapture(_ url: URL) -> Bool {
        managedStem(in: url.lastPathComponent, suffix: ".png") != nil
            && !url.lastPathComponent.hasSuffix(".source.png")
    }

    public static func isManagedCaptureFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return managedStem(in: name, suffix: ".png") != nil
            || managedStem(in: name, suffix: ".source.png") != nil
            || managedStem(in: name, suffix: ".project.json") != nil
    }

    public static func isRegularManagedCaptureFile(_ url: URL) -> Bool {
        guard isManagedCaptureFile(url),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    public static func regularManagedCaptureFiles(in urls: [URL]) -> [URL] {
        urls.filter(isRegularManagedCaptureFile)
    }

    private static func managedStem(in fileName: String, suffix: String) -> Substring? {
        guard fileName.hasSuffix(suffix) else { return nil }
        let stem = fileName.dropLast(suffix.count)
        guard stem.range(of: stemPattern, options: .regularExpression) != nil else { return nil }
        return stem
    }
}
