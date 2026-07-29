import CoreGraphics

/// Куда поставить панель-рельс с растущей склейкой.
///
/// Панель живёт сбоку от выбранной рамки и никогда не наезжает на неё: содержимое,
/// которое пользователь прокручивает, должно оставаться открытым.
public enum ScrollCapturePreviewPlacement {
    public struct Metrics: Equatable, Sendable {
        public var width: CGFloat
        public var minimumHeight: CGFloat
        public var maximumHeight: CGFloat
        public var gap: CGFloat
        public var margin: CGFloat

        public init(
            width: CGFloat = 244,
            minimumHeight: CGFloat = 160,
            maximumHeight: CGFloat = 420,
            gap: CGFloat = 20,
            margin: CGFloat = 12
        ) {
            self.width = width
            self.minimumHeight = minimumHeight
            self.maximumHeight = maximumHeight
            self.gap = gap
            self.margin = margin
        }
    }

    /// Возвращает кадр панели в координатах AppKit или nil, если сбоку от рамки нет места.
    public static func frame(
        near captureRect: CGRect,
        visibleFrame: CGRect,
        metrics: Metrics = Metrics()
    ) -> CGRect? {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return nil }

        let height = min(
            max(metrics.minimumHeight, min(captureRect.height, metrics.maximumHeight)),
            max(metrics.minimumHeight, visibleFrame.height - metrics.margin * 2)
        )
        guard height > 0 else { return nil }

        let rightX = captureRect.maxX + metrics.gap
        let leftX = captureRect.minX - metrics.gap - metrics.width
        let x: CGFloat
        if rightX + metrics.width + metrics.margin <= visibleFrame.maxX {
            x = rightX
        } else if leftX - metrics.margin >= visibleFrame.minX {
            x = leftX
        } else {
            return nil
        }

        let centred = captureRect.midY - height / 2
        let minimumY = visibleFrame.minY + metrics.margin
        let maximumY = max(minimumY, visibleFrame.maxY - height - metrics.margin)
        let y = min(max(centred, minimumY), maximumY)

        return CGRect(x: x, y: y, width: metrics.width, height: height)
    }
}
