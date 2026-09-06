import Foundation

public enum ApplicationInstallPolicy {
    public static func destinationURL(homeDirectory: URL, appBundleName: String) -> URL {
        homeDirectory
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent(appBundleName, isDirectory: true)
    }

    public static func isInstalled(bundleURL: URL, homeDirectory: URL) -> Bool {
        isInside(bundleURL, directory: URL(fileURLWithPath: "/Applications", isDirectory: true))
            || isInside(
                bundleURL,
                directory: homeDirectory.appendingPathComponent("Applications", isDirectory: true)
            )
    }

    public static func cleanupCandidate(
        sourceBundleURL: URL,
        installedBundleURL: URL,
        userApprovedCleanup: Bool
    ) -> URL? {
        guard userApprovedCleanup,
              canonical(sourceBundleURL) != canonical(installedBundleURL) else { return nil }
        return sourceBundleURL
    }

    private static func isInside(_ candidate: URL, directory: URL) -> Bool {
        let candidateComponents = canonical(candidate).pathComponents
        let directoryComponents = canonical(directory).pathComponents
        guard candidateComponents.count > directoryComponents.count else { return false }
        return candidateComponents.prefix(directoryComponents.count).elementsEqual(directoryComponents)
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

public enum ApplicationBundleInstallError: LocalizedError {
    case recoveryFailed(backupURL: URL)

    public var errorDescription: String? {
        switch self {
        case let .recoveryFailed(backupURL):
            "Не удалось восстановить предыдущую версию. Резервная копия сохранена: \(backupURL.path)"
        }
    }
}

public enum ApplicationBundleInstaller {
    public static func install(
        sourceBundleURL: URL,
        destinationBundleURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let parent = destinationBundleURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let nonce = UUID().uuidString
        let staging = parent.appendingPathComponent(".ScreenshotApp-installing-\(nonce).app", isDirectory: true)
        let backup = parent.appendingPathComponent(".ScreenshotApp-backup-\(nonce).app", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: staging)
        }

        try fileManager.copyItem(at: sourceBundleURL, to: staging)
        let hadExistingDestination = fileManager.fileExists(atPath: destinationBundleURL.path)
        if hadExistingDestination {
            try fileManager.moveItem(at: destinationBundleURL, to: backup)
        }

        do {
            try fileManager.moveItem(at: staging, to: destinationBundleURL)
        } catch {
            if hadExistingDestination,
               !fileManager.fileExists(atPath: destinationBundleURL.path),
               fileManager.fileExists(atPath: backup.path) {
                do {
                    try fileManager.moveItem(at: backup, to: destinationBundleURL)
                } catch {
                    throw ApplicationBundleInstallError.recoveryFailed(backupURL: backup)
                }
            }
            throw error
        }
        // Remove the previous application only after its replacement succeeded.
        try? fileManager.removeItem(at: backup)
    }
}
