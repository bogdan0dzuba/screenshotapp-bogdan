# Persistent Scroll Capture Trail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Исправить ложную потерю перекрытия, сохранить hover-safe первый кадр и показывать постоянный голубой след снятого объёма за выбранной рамкой без мигания HUD.

**Architecture:** Output-последовательность и classification-последовательность разделяются. Первый output остаётся `selection.image`, filtered baseline и следующие filtered-кадры используются для решений classifier, а подтверждённые overlap вместе с направлением сохраняются в `ScrollCaptureSession` и повторно применяются при финальной склейке. Экранный trail остаётся чистым AppKit overlay без bitmap и не попадает в захват.

**Tech Stack:** Swift 6 toolchain в Swift 5 language mode, SwiftUI, AppKit, ScreenCaptureKit, CoreGraphics, SwiftPM, shell contract checks.

## Global Constraints

- Минимальная платформа остаётся macOS 14.
- Новые зависимости не добавляются.
- `selection.image` остаётся первым output-кадром.
- Settle-интервал равен 0,32 секунды.
- Максимум равен 80 кадрам.
- Overlay должен иметь `sharingType = .none` и `ignoresMouseEvents = true`.
- Изменение проекта сопровождается обновлением `docs/changelog/CHANGELOG.md`.

---

### Task 1: Постоянный внешний trail и стабильный HUD

**Files:**
- Create: `Sources/ScreenshotCore/Scrolling/ScrollCaptureTrail.swift`
- Modify: `Sources/ScreenshotApp/Windowing/ScrollCaptureController.swift`
- Modify: `Sources/ScreenshotApp/Views/ScrollCaptureControlsView.swift`
- Modify: `Sources/ScreenshotCore/Scrolling/ScrollCaptureCoverageView.swift`
- Modify: `Sources/ScreenshotCore/Scrolling/ScrollFrameSettler.swift`
- Test: `Tests/CoreChecks/main.swift`
- Test: `Tests/ScrollCaptureInteractionChecks.sh`

**Interfaces:**
- Consumes: `ScrollCaptureDirection`, classifier-approved overlap и capture rect.
- Produces: `ScrollCaptureTrail.append`, `prepend`, `undoLast`, `reset`, `externalRect`.

- [x] **Step 1: Добавить RED-проверки внешнего следа и стабильного HUD**

```bash
bash Tests/ScrollCaptureInteractionChecks.sh
```

Expected: FAIL до появления `ScrollCaptureTrail`, screen-sized overlay и удаления poll-spinner/flash.

- [x] **Step 2: Реализовать модель накопленного следа**

```swift
public mutating func append(frameHeight: Int, overlap: Int, captureHeight: CGFloat)
public mutating func prepend(frameHeight: Int, overlap: Int, captureHeight: CGFloat)
public mutating func undoLast()
public func externalRect(
    captureRect: CGRect,
    screenRect: CGRect,
    direction: ScrollCaptureDirection
) -> CGRect
```

- [x] **Step 3: Перевести coverage overlay на размер дисплея**

`ScrollCaptureCoverageView.configure(captureRect:screenRect:trail:)` получает локальную геометрию рамки и рисует `externalTrailRects` голубым с alpha 0,24.

- [x] **Step 4: Удалить poll-мигание**

Удалить `ProgressView`, per-poll отключение действий, Return shortcut и `CAKeyframeAnimation`. Оставить устойчивый цвет для каждого `ScrollCaptureFeedbackState`.

- [x] **Step 5: Проверить задачу**

```bash
bash Tests/ScrollCaptureInteractionChecks.sh
swift run --disable-sandbox CoreChecks
```

Expected: обе проверки PASS.

### Task 2: Stable filtered baseline после «Начать»

**Files:**
- Modify: `Sources/ScreenshotApp/Windowing/ScrollCaptureController.swift`
- Test: `Tests/HoverPreservationChecks.sh`
- Test: `Tests/ScrollCaptureInteractionChecks.sh`
- Test: `Tests/CoreChecks/main.swift`

**Interfaces:**
- Consumes: `PreparedScrollCapture`, `CaptureService.capture(_:to:)`, `ScrollFrameNormalizer.normalized`.
- Produces: `classificationFrames: [CGImage]` и baseline-only подготовку без изменения `frameCount`.

- [x] **Step 1: Написать RED-контракт**

```bash
bash Tests/ScrollCaptureInteractionChecks.sh
```

Expected: FAIL с сообщением, что hover-safe output всё ещё используется как automatic comparison baseline.

- [x] **Step 2: Подготовить baseline до запуска poll-loop**

```swift
private func prepareStableBaseline(
    firstFrame: CGImage,
    preparedCapture: PreparedScrollCapture,
    captureService: CaptureService,
    generation: Int
) async
```

Функция снимает filtered frame, нормализует его к размеру `selection.image`, сохраняет в `classificationFrames`, затем создаёт output-session с исходным `firstFrame`.

- [x] **Step 3: Сравнивать автоматический кадр с classification baseline**

В `captureAutomaticFrame()` брать `classificationFrames.last`, а после commit добавлять normalized frame в history. При undo удалять последний classification frame вместе с output-кадром.

- [x] **Step 4: Проверить hover-контракт**

```bash
bash Tests/HoverPreservationChecks.sh
bash Tests/ScrollCaptureInteractionChecks.sh
```

Expected: обе проверки PASS.

### Task 3: Сохранённые seams для финальной склейки

**Files:**
- Modify: `Sources/ScreenshotCore/Scrolling/ScrollCaptureSession.swift`
- Modify: `Sources/ScreenshotCore/Scrolling/ScrollStitcher.swift`
- Modify: `Sources/ScreenshotApp/Windowing/ScrollCaptureController.swift`
- Test: `Tests/CoreChecks/main.swift`

**Interfaces:**
- Produces: `ScrollCaptureSession.add(_:direction:overlap:)`, `stitchSeams`, `ScrollStitcher.stitch(_:seams:)`.
- Consumes: overlap из `.append(overlap:)` или `.prepend(overlap:)`.

- [x] **Step 1: Добавить RED-тест hover-safe первого шва**

```swift
let output = try ScrollStitcher.stitch(
    [hoverPreservedFirst, filteredAfterScroll],
    seams: [.append(overlap: 3)]
)
```

Expected before implementation: compile failure `extra argument 'overlaps' in call`.

- [x] **Step 2: Добавить валидируемый overload склейщика**

```swift
public static func stitch(_ frames: [CGImage], seams: [ScrollStitchSeam]) throws -> CGImage
```

Количество seams должно равняться `frames.count - 1`, каждый overlap должен быть неотрицательным и меньше высоты соседних кадров. Все seams одного результата имеют направление append или prepend.

- [x] **Step 3: Хранить seam рядом с output-порядком**

При `.down` добавлять `.append` seam в конец, при `.up` вставлять `.prepend` в начало. `undoLastFrame()` удаляет seam с той же стороны.

- [x] **Step 4: Передать seams в final stitch**

Контроллер извлекает `session.stitchSeams` и вызывает directional-seam overload внутри detached stitching task. Pixel-тест вверх подтверждает, что перед полным hover-safe кадром добавляются только новые верхние строки.

- [x] **Step 5: Запустить CoreChecks**

```bash
swift run --disable-sandbox CoreChecks
```

Expected: `CoreChecks: OK`.

### Task 4: Документация, установка и live-приёмка

**Files:**
- Modify: `README.md`
- Modify: `docs/changelog/CHANGELOG.md`
- Create: `docs/superpowers/specs/2026-07-29-scroll-capture-persistent-trail-design.md`

**Interfaces:**
- Consumes: готовую подписанную локальную сборку.
- Produces: проверяемое описание текущего поведения и установленное приложение.

- [x] **Step 1: Обновить README и changelog**

Убрать устаревшие обещания bitmap-плашки «СНЯТО ✓» и зелёной flash-анимации. Описать внешний голубой след и baseline-подготовку.

- [x] **Step 2: Выполнить полную локальную проверку и установку**

```bash
bash script/build_and_run.sh --verify
git diff --check
```

Expected: все contract checks, сборка, подпись и установка PASS.

- [ ] **Step 3: Выполнить live-сценарий на Notion**

Без прокрутки после Start нет warning; после малого scroll счётчик становится минимум 2; внешний cyan trail виден за рамкой; HUD устойчив; «Готово» открывает длинный PNG.

- [x] **Step 4: Зафиксировать результат**

```bash
git add README.md Sources Tests docs
git commit -m "Fix scrolling capture baseline and trail"
```

Expected: чистый worktree и локальный commit без push или релиза.
