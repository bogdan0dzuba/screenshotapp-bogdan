public enum ShelfWindowResizePolicy {
    public static func shouldPersist(
        isExpanded: Bool,
        isApplyingPresentation: Bool,
        isLiveResize: Bool
    ) -> Bool {
        isExpanded && !isApplyingPresentation && isLiveResize
    }
}
