import CoreGraphics

public struct ScrollAutoAdvanceStep: Equatable, Sendable {
    /// Сколько точек прокрутить за один шаг. Знак задаёт направление: вниз - отрицательный.
    public var wheelDelta: Int
    /// Сколько ждать после шага, чтобы кадр успел устояться и попасть в склейку.
    public var settleSeconds: Double

    public init(wheelDelta: Int, settleSeconds: Double) {
        self.wheelDelta = wheelDelta
        self.settleSeconds = settleSeconds
    }
}

/// Решения автопрокрутки: насколько двигать страницу и когда останавливаться.
///
/// Шаг заведомо меньше высоты рамки, иначе соседние кадры перестанут перекрываться
/// и классификатор отвергнет их как потерю перекрытия.
public enum ScrollAutoAdvancePolicy {
    public static let minimumStep = 40
    public static let maximumStep = 600
    /// Столько шагов подряд без нового кадра считается концом страницы.
    public static let idleRoundsBeforeStop = 3

    public static func step(
        captureHeight: CGFloat,
        direction: ScrollCaptureDirection
    ) -> ScrollAutoAdvanceStep {
        let raw = Int((captureHeight / 3).rounded())
        let magnitude = min(maximumStep, max(minimumStep, raw))
        // Один цикл опроса - 0,36 с, стабилизация - 0,32 с. Ждём с запасом,
        // иначе автопрокрутка обгонит собственную склейку.
        return ScrollAutoAdvanceStep(
            wheelDelta: direction == .down ? -magnitude : magnitude,
            settleSeconds: 0.85
        )
    }

    public static func shouldStop(
        idleRounds: Int,
        frameCount: Int,
        maximumFrameCount: Int
    ) -> Bool {
        idleRounds >= idleRoundsBeforeStop || frameCount >= maximumFrameCount
    }

    public static func reachedEndOfPage(idleRounds: Int) -> Bool {
        idleRounds >= idleRoundsBeforeStop
    }
}
