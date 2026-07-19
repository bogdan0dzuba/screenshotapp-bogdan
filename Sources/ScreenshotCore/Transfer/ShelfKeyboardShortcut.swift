import AppKit

public enum ShelfKeyboardShortcut {
    public static func isCopy(
        key: String,
        keyCode: UInt16? = nil,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let isCKey = key.lowercased() == "c" || keyCode == 8
        guard isCKey, !modifiers.contains(.option) else { return false }
        return modifiers.contains(.command) || modifiers.contains(.control)
    }

    public static func shouldCopy(
        key: String,
        keyCode: UInt16? = nil,
        modifiers: NSEvent.ModifierFlags,
        eventWindowNumber: Int,
        panelWindowNumber: Int,
        panelIsKey: Bool
    ) -> Bool {
        isCopy(key: key, keyCode: keyCode, modifiers: modifiers)
            && (panelIsKey || eventWindowNumber == panelWindowNumber)
    }
}
