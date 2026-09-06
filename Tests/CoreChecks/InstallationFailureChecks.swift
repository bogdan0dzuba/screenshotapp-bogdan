import Foundation
import ScreenshotCore

private final class FailingInstallFileManager: FileManager, @unchecked Sendable {
    let failRollback: Bool
    init(failRollback: Bool) { self.failRollback = failRollback; super.init() }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.lastPathComponent.hasPrefix(".ScreenshotApp-installing-") ||
            (failRollback && srcURL.lastPathComponent.hasPrefix(".ScreenshotApp-backup-")) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

func checkInstallationFailureRecovery() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("InstallFailure-\(UUID())")
    defer { try? fm.removeItem(at: root) }
    for failRollback in [false, true] {
        let folder = root.appendingPathComponent(String(failRollback))
        let source = folder.appendingPathComponent("Source.app")
        let target = folder.appendingPathComponent("Applications/Target.app")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: source.appendingPathComponent("payload"))
        try Data("old".utf8).write(to: target.appendingPathComponent("payload"))
        var failed = false
        var failureDescription = ""
        do {
            try ApplicationBundleInstaller.install(sourceBundleURL: source, destinationBundleURL: target,
                                                   fileManager: FailingInstallFileManager(failRollback: failRollback))
        } catch { failed = true; failureDescription = error.localizedDescription }
        guard failed else { throw NSError(domain: "installation must report failure", code: 1) }
        let siblings = try fm.contentsOfDirectory(at: target.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        let backups = siblings.filter { $0.lastPathComponent.hasPrefix(".ScreenshotApp-backup-") }
        let recoveryURL: URL
        if failRollback {
            guard backups.count == 1 else {
                throw NSError(domain: "failed rollback must preserve the old application backup", code: 1)
            }
            recoveryURL = backups[0]
            guard failureDescription.contains(recoveryURL.lastPathComponent) else {
                throw NSError(domain: "recovery error must expose backup location", code: 1)
            }
        } else {
            guard backups.isEmpty else { throw NSError(domain: "successful rollback leaves no backup", code: 1) }
            recoveryURL = target
        }
        guard try String(contentsOf: recoveryURL.appendingPathComponent("payload"), encoding: .utf8) == "old" else {
            throw NSError(domain: "old application contents must survive", code: 1)
        }
        guard !siblings.contains(where: { $0.lastPathComponent.hasPrefix(".ScreenshotApp-installing-") }) else {
            throw NSError(domain: "staging cleanup failed", code: 1)
        }
    }
}
