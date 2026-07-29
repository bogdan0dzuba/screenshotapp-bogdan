public enum ScrollCapturePreviewTone: Equatable, Sendable {
    case neutral
    case aligning
    case accepted
    case warning
    case working
}

public struct ScrollCapturePreviewBadge: Equatable, Sendable {
    public var title: String
    public var tone: ScrollCapturePreviewTone

    public init(title: String, tone: ScrollCapturePreviewTone) {
        self.title = title
        self.tone = tone
    }
}

/// Подпись под растущим превью. Заменяет цвет рамки как основной сигнал состояния:
/// цвет читается только боковым зрением, а слово - сразу.
public enum ScrollCapturePreviewBadgePolicy {
    public static func badge(
        state: ScrollCaptureFeedbackState,
        isPaused: Bool,
        isFinalizing: Bool
    ) -> ScrollCapturePreviewBadge {
        if isFinalizing {
            return ScrollCapturePreviewBadge(title: "Сшиваю", tone: .working)
        }
        if isPaused {
            return ScrollCapturePreviewBadge(title: "Пауза", tone: .neutral)
        }
        switch state {
        case .ready:
            return ScrollCapturePreviewBadge(title: "Жду прокрутки", tone: .neutral)
        case .aligning:
            return ScrollCapturePreviewBadge(title: "Догоняю", tone: .aligning)
        case .acceptedDown, .acceptedUp:
            return ScrollCapturePreviewBadge(title: "Кадр принят", tone: .accepted)
        case .needsOverlap:
            return ScrollCapturePreviewBadge(title: "Верните перекрытие", tone: .warning)
        }
    }
}
