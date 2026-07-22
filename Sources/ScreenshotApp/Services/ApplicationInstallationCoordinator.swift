import AppKit
import ScreenshotCore

@MainActor
final class ApplicationInstallationCoordinator {
    private let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func offerInstallationIfNeeded() -> Bool {
        let sourceBundleURL = Bundle.main.bundleURL
        guard !ApplicationInstallPolicy.isInstalled(
            bundleURL: sourceBundleURL,
            homeDirectory: homeDirectory
        ) else { return false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Установить «Богдан Скриншот»?"
        alert.informativeText = "Приложение будет скопировано в вашу папку «Программы» и запущено оттуда."
        alert.addButton(withTitle: "Установить")
        alert.addButton(withTitle: "Не сейчас")
        let cleanupCheckbox = NSButton(
            checkboxWithTitle: "После установки переместить скачанную копию в Корзину",
            target: nil,
            action: nil
        )
        cleanupCheckbox.state = .on
        alert.accessoryView = cleanupCheckbox

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let destination = ApplicationInstallPolicy.destinationURL(
            homeDirectory: homeDirectory,
            appBundleName: sourceBundleURL.lastPathComponent
        )
        do {
            try ApplicationBundleInstaller.install(
                sourceBundleURL: sourceBundleURL,
                destinationBundleURL: destination
            )
        } catch {
            showFailure("Не удалось установить приложение: \(error.localizedDescription)")
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    self.showFailure("Приложение установлено, но не удалось его открыть: \(error.localizedDescription)")
                    return
                }
                if let cleanupURL = ApplicationInstallPolicy.cleanupCandidate(
                    sourceBundleURL: sourceBundleURL,
                    installedBundleURL: destination,
                    userApprovedCleanup: cleanupCheckbox.state == .on
                ) {
                    try? FileManager.default.trashItem(at: cleanupURL, resultingItemURL: nil)
                }
                NSApp.terminate(nil)
            }
        }
        return true
    }

    private func showFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Установка не завершена"
        alert.informativeText = message
        alert.runModal()
    }
}
