public enum ScrollCaptureDirectionPolicy {
    public static func accepts(
        _ decision: ScrollFrameDecision,
        lockedTo direction: ScrollCaptureDirection?
    ) -> Bool {
        guard let direction else { return true }
        switch (direction, decision) {
        case (.down, .append), (.up, .prepend), (_, .unchanged), (_, .insufficientOverlap):
            return true
        case (.down, .prepend), (.up, .append):
            return false
        }
    }
}
