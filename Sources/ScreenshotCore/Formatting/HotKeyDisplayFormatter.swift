public enum HotKeyDisplayFormatter {
    public static func symbolic(_ hotKey: HotKey) -> String {
        var value = ""
        if hotKey.modifiers.contains(.command) { value += "⌘" }
        if hotKey.modifiers.contains(.shift) { value += "⇧" }
        if hotKey.modifiers.contains(.option) { value += "⌥" }
        if hotKey.modifiers.contains(.control) { value += "⌃" }
        return value + hotKey.key
    }

    public static func readable(_ hotKey: HotKey) -> String {
        var parts: [String] = []
        if hotKey.modifiers.contains(.command) { parts.append("Command (⌘)") }
        if hotKey.modifiers.contains(.shift) { parts.append("Shift (⇧)") }
        if hotKey.modifiers.contains(.option) { parts.append("Option (⌥)") }
        if hotKey.modifiers.contains(.control) { parts.append("Control (⌃)") }
        parts.append(hotKey.key)
        return parts.joined(separator: " + ")
    }
}
