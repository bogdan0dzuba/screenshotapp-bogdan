import AppKit
import Foundation
import ScreenshotCore

@MainActor
final class AppPreferences: ObservableObject {
    enum ImageFormat: String, CaseIterable, Identifiable {
        case png
        case jpeg

        var id: String { rawValue }
        var title: String { self == .png ? "PNG" : "JPEG" }
    }

    private enum Key {
        static let folder = "captureFolder"
        static let hotKeyLetter = "hotKeyLetter"
        static let hotKeyCommand = "hotKeyCommand"
        static let hotKeyShift = "hotKeyShift"
        static let hotKeyOption = "hotKeyOption"
        static let hotKeyControl = "hotKeyControl"
        static let imageFormat = "imageFormat"
        static let closeEditorAfterCopy = "closeEditorAfterCopy"
        static let maximumCount = "maximumCount"
        static let maximumAgeDays = "maximumAgeDays"
        static let historyFraction = "historyFraction"
        static let historyFractionRevision = "historyFractionRevision"
        static let shelfTransparency = "shelfTransparency"
    }

    @Published var captureFolder: URL { didSet { defaults.set(captureFolder.path, forKey: Key.folder) } }
    @Published var hotKeyLetter: String { didSet { defaults.set(hotKeyLetter, forKey: Key.hotKeyLetter) } }
    @Published var useCommand: Bool { didSet { defaults.set(useCommand, forKey: Key.hotKeyCommand) } }
    @Published var useShift: Bool { didSet { defaults.set(useShift, forKey: Key.hotKeyShift) } }
    @Published var useOption: Bool { didSet { defaults.set(useOption, forKey: Key.hotKeyOption) } }
    @Published var useControl: Bool { didSet { defaults.set(useControl, forKey: Key.hotKeyControl) } }
    @Published var imageFormat: ImageFormat { didSet { defaults.set(imageFormat.rawValue, forKey: Key.imageFormat) } }
    @Published var closeEditorAfterCopy: Bool {
        didSet { defaults.set(closeEditorAfterCopy, forKey: Key.closeEditorAfterCopy) }
    }
    @Published var maximumCount: Int {
        didSet {
            maximumCount = min(max(1, maximumCount), HistoryRetentionPolicy.maximumCaptures)
            defaults.set(maximumCount, forKey: Key.maximumCount)
        }
    }
    @Published var maximumAgeDays: Int { didSet { defaults.set(maximumAgeDays, forKey: Key.maximumAgeDays) } }
    @Published var historyFraction: Double {
        didSet {
            let constrained = ShelfSplitLayout.historyFraction(historyFraction)
            guard constrained == historyFraction else {
                historyFraction = constrained
                return
            }
            defaults.set(constrained, forKey: Key.historyFraction)
        }
    }
    @Published var shelfTransparency: Double {
        didSet {
            let constrained = Self.clampedTransparency(shelfTransparency)
            guard constrained == shelfTransparency else {
                shelfTransparency = constrained
                return
            }
            defaults.set(constrained, forKey: Key.shelfTransparency)
        }
    }

    let availableLetters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    private let defaults: UserDefaults
    static let defaultShelfTransparency = 0.35
    static let currentHistoryFractionRevision = 2

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = Self.defaultCaptureFolder()
        captureFolder = defaults.string(forKey: Key.folder).map(URL.init(fileURLWithPath:)) ?? fallback
        hotKeyLetter = defaults.string(forKey: Key.hotKeyLetter) ?? "A"
        useCommand = defaults.object(forKey: Key.hotKeyCommand) as? Bool ?? true
        useShift = defaults.object(forKey: Key.hotKeyShift) as? Bool ?? true
        useOption = defaults.object(forKey: Key.hotKeyOption) as? Bool ?? false
        useControl = defaults.object(forKey: Key.hotKeyControl) as? Bool ?? false
        imageFormat = ImageFormat(rawValue: defaults.string(forKey: Key.imageFormat) ?? "png") ?? .png
        closeEditorAfterCopy = defaults.object(forKey: Key.closeEditorAfterCopy) as? Bool ?? true
        let storedMaximumCount = defaults.object(forKey: Key.maximumCount) as? Int
            ?? HistoryRetentionPolicy.maximumCaptures
        maximumCount = min(max(1, storedMaximumCount), HistoryRetentionPolicy.maximumCaptures)
        maximumAgeDays = defaults.object(forKey: Key.maximumAgeDays) as? Int ?? 30
        let storedHistoryFraction = (defaults.object(forKey: Key.historyFraction) as? NSNumber)?.doubleValue
        let storedHistoryFractionRevision = defaults.integer(forKey: Key.historyFractionRevision)
        if storedHistoryFractionRevision < Self.currentHistoryFractionRevision,
           storedHistoryFraction == nil || abs((storedHistoryFraction ?? 0.3) - 0.3) < 0.000_001 {
            historyFraction = ShelfSplitLayout.defaultHistoryFraction
        } else {
            historyFraction = ShelfSplitLayout.historyFraction(
                storedHistoryFraction ?? ShelfSplitLayout.defaultHistoryFraction
            )
        }
        let storedTransparency = (defaults.object(forKey: Key.shelfTransparency) as? NSNumber)?.doubleValue
            ?? Self.defaultShelfTransparency
        shelfTransparency = Self.clampedTransparency(storedTransparency)
        defaults.set(maximumCount, forKey: Key.maximumCount)
        defaults.set(historyFraction, forKey: Key.historyFraction)
        defaults.set(Self.currentHistoryFractionRevision, forKey: Key.historyFractionRevision)
        defaults.set(shelfTransparency, forKey: Key.shelfTransparency)
    }

    var hotKey: HotKey {
        var modifiers: HotKeyModifiers = []
        if useCommand { modifiers.insert(.command) }
        if useShift { modifiers.insert(.shift) }
        if useOption { modifiers.insert(.option) }
        if useControl { modifiers.insert(.control) }
        return HotKey(
            key: hotKeyLetter,
            keyCode: Self.keyCodes[hotKeyLetter] ?? 0,
            modifiers: modifiers
        )
    }

    static func defaultCaptureFolder() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codex = home.appendingPathComponent("Documents/Codex", isDirectory: true)
        if FileManager.default.fileExists(atPath: codex.path) {
            return codex.appendingPathComponent("Screenshots", isDirectory: true)
        }
        return home.appendingPathComponent("Pictures/ScreenshotApp", isDirectory: true)
    }

    private static func clampedTransparency(_ value: Double) -> Double {
        guard value.isFinite else { return defaultShelfTransparency }
        return min(max(value, 0), 1)
    }

    static let keyCodes: [String: UInt32] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
        "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15,
        "Y": 16, "T": 17, "O": 31, "U": 32, "I": 34, "P": 35, "L": 37,
        "J": 38, "K": 40, "N": 45, "M": 46,
    ]
}
