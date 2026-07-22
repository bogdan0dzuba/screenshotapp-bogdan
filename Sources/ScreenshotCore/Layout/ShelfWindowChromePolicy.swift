public enum ShelfWindowChromePolicy {
    public static func showsCustomControls(in state: ShelfState) -> Bool {
        if case .expanded = state { return true }
        return false
    }
}
