public enum ActiveHotKeyFormatter {
    public static func symbolic(_ hotKey: HotKey?) -> String {
        hotKey.map(HotKeyDisplayFormatter.symbolic) ?? "—"
    }

    public static func readable(_ hotKey: HotKey?) -> String {
        hotKey.map(HotKeyDisplayFormatter.readable) ?? "Не назначена"
    }
}

public enum HotKeyStartupPolicy {
    public static func candidates(preferred: HotKey) -> [HotKey] {
        preferred == .defaultCapture ? [preferred] : [preferred, .defaultCapture]
    }
}
