# ScreenshotApp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Собрать нативный русскоязычный macOS-скриншотер с захватом, редактором, OCR, прокручиваемой склейкой и полкой истории.

**Architecture:** SwiftPM содержит тестируемую библиотеку `ScreenshotCore` и GUI-исполняемый модуль `ScreenshotApp`. SwiftUI владеет состоянием и интерфейсом, а узкие AppKit-сервисы управляют системным хоткеем, окнами, захватом, буфером и drag-and-drop.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Vision, Core Image, Core Graphics, Carbon, XCTest/Swift Testing, macOS 14+.

## Global Constraints

- Весь пользовательский текст - на русском.
- Начальный хоткей - `⌘⇧A`, он изменяется в настройках.
- Никакой сети, телеметрии, аккаунтов и видео.
- Снимки сохраняются обычными файлами в доступной пользователю и агентам папке.
- Все новые тестируемые функции проходят RED -> GREEN.

---

### Task 1: Core models and persistence contracts

**Files:**
- Create: `Package.swift`
- Create: `Sources/ScreenshotCore/Models/Annotation.swift`
- Create: `Sources/ScreenshotCore/Models/CaptureItem.swift`
- Create: `Sources/ScreenshotCore/Models/EditorDocument.swift`
- Create: `Sources/ScreenshotCore/Models/HotKey.swift`
- Create: `Sources/ScreenshotCore/Stores/HistoryIndex.swift`
- Test: `Tests/ScreenshotCoreTests/CoreModelsTests.swift`

**Interfaces:**
- Produces: `Annotation`, `CaptureItem`, `EditorDocument`, `HotKey`, `HistoryIndex` as `Codable`, `Equatable`, `Sendable` value types.

- [ ] **Step 1: Write failing model tests**

```swift
@Test func documentRoundTrips() throws {
  let value = EditorDocument(imageFileName: "capture.png", canvasSize: .init(width: 120, height: 80), annotations: [.rectangle(.init(x: 0.1, y: 0.1, width: 0.4, height: 0.3), style: .red)])
  #expect(try JSONDecoder().decode(EditorDocument.self, from: JSONEncoder().encode(value)) == value)
}

@Test func historyKeepsNewestWithinLimits() {
  let result = HistoryIndex.pruned(items: fixtures, maximumCount: 2, maximumAgeDays: 30, now: now)
  #expect(result.map(\.id) == [fixtures[2].id, fixtures[1].id])
}
```

- [ ] **Step 2: Run RED**

Run: `swift test --filter CoreModelsTests`
Expected: FAIL because the target and types do not exist.

- [ ] **Step 3: Implement the value types and pure pruning function**

```swift
public struct EditorDocument: Codable, Equatable, Sendable {
  public var imageFileName: String
  public var canvasSize: CanvasSize
  public var annotations: [Annotation]
}

public enum HistoryIndex {
  public static func pruned(items: [CaptureItem], maximumCount: Int, maximumAgeDays: Int, now: Date) -> [CaptureItem]
}
```

- [ ] **Step 4: Run GREEN**

Run: `swift test --filter CoreModelsTests`
Expected: PASS.

### Task 2: Editor state and renderer

**Files:**
- Create: `Sources/ScreenshotCore/Editor/EditorState.swift`
- Create: `Sources/ScreenshotCore/Editor/AnnotationRenderer.swift`
- Create: `Sources/ScreenshotCore/Editor/ImageEffects.swift`
- Test: `Tests/ScreenshotCoreTests/EditorStateTests.swift`
- Test: `Tests/ScreenshotCoreTests/AnnotationRendererTests.swift`

**Interfaces:**
- Consumes: `Annotation`, `EditorDocument`.
- Produces: `EditorState.add(_:)`, `undo()`, `redo()`, `deleteSelected()` and `AnnotationRenderer.render(baseImage:document:) -> CGImage`.

- [ ] **Step 1: Write failing Undo/Redo and renderer-size tests**

```swift
@Test func undoAndRedoRestoreLayers() {
  var state = EditorState(document: .empty)
  state.add(.line(from: .zero, to: .init(x: 1, y: 1), style: .red))
  state.undo()
  #expect(state.document.annotations.isEmpty)
  state.redo()
  #expect(state.document.annotations.count == 1)
}

@Test func renderedImageKeepsPixelSize() throws {
  let output = try AnnotationRenderer.render(baseImage: fixtureImage, document: .empty)
  #expect(output.width == fixtureImage.width)
  #expect(output.height == fixtureImage.height)
}
```

- [ ] **Step 2: Run RED**

Run: `swift test --filter EditorStateTests && swift test --filter AnnotationRendererTests`
Expected: FAIL because editor types are missing.

- [ ] **Step 3: Implement immutable snapshots and Core Graphics/Core Image rendering**

```swift
public struct EditorState {
  public private(set) var document: EditorDocument
  public mutating func add(_ annotation: Annotation)
  public mutating func undo()
  public mutating func redo()
  public mutating func deleteSelected()
}

public enum AnnotationRenderer {
  public static func render(baseImage: CGImage, document: EditorDocument) throws -> CGImage
}
```

- [ ] **Step 4: Run GREEN**

Run: `swift test --filter EditorStateTests && swift test --filter AnnotationRendererTests`
Expected: PASS.

### Task 3: Scrolling overlap and stitching

**Files:**
- Create: `Sources/ScreenshotCore/Scrolling/OverlapMatcher.swift`
- Create: `Sources/ScreenshotCore/Scrolling/ScrollStitcher.swift`
- Test: `Tests/ScreenshotCoreTests/ScrollStitcherTests.swift`

**Interfaces:**
- Produces: `OverlapMatcher.bestVerticalOverlap(previous:next:)` and `ScrollStitcher.stitch(_:)`.

- [ ] **Step 1: Write synthetic-image tests first**

```swift
@Test func findsKnownVerticalOverlap() throws {
  let (first, second) = Fixtures.scrollingFrames(overlap: 24)
  #expect(try OverlapMatcher.bestVerticalOverlap(previous: first, next: second) == 24)
}

@Test func stitchRemovesRepeatedRows() throws {
  let output = try ScrollStitcher.stitch([first, second])
  #expect(output.height == first.height + second.height - 24)
}
```

- [ ] **Step 2: Run RED**

Run: `swift test --filter ScrollStitcherTests`
Expected: FAIL because stitching APIs are missing.

- [ ] **Step 3: Implement downsampled grayscale matching and CGContext composition**

```swift
public enum OverlapMatcher {
  public static func bestVerticalOverlap(previous: CGImage, next: CGImage) throws -> Int
}

public enum ScrollStitcher {
  public static func stitch(_ frames: [CGImage]) throws -> CGImage
}
```

- [ ] **Step 4: Run GREEN**

Run: `swift test --filter ScrollStitcherTests`
Expected: PASS.

### Task 4: Capture, hotkey and history services

**Files:**
- Create: `Sources/ScreenshotApp/Services/CaptureService.swift`
- Create: `Sources/ScreenshotApp/Services/GlobalHotKeyService.swift`
- Create: `Sources/ScreenshotApp/Services/HistoryStore.swift`
- Create: `Sources/ScreenshotApp/Services/PasteboardService.swift`
- Create: `Sources/ScreenshotApp/Support/AppPreferences.swift`
- Create: `Sources/ScreenshotApp/Views/RegionSelectionView.swift`
- Create: `Sources/ScreenshotApp/Windowing/RegionSelectionController.swift`

**Interfaces:**
- Consumes: core `CaptureItem`, `HotKey`, `HistoryIndex`.
- Produces: `CaptureService.capture(rect:to:)`, `HistoryStore.importCapture(at:)`, `GlobalHotKeyService.register(_:)`.

- [ ] **Step 1: Add protocol-level tests using real temporary folders**

```swift
@Test func importingPNGCreatesProjectAndNewestHistoryItem() async throws {
  let store = try HistoryStore(folder: temporaryFolder)
  let item = try await store.importCapture(at: fixturePNG)
  #expect(FileManager.default.fileExists(atPath: item.imageURL.path))
  #expect(store.items.first?.id == item.id)
}
```

- [ ] **Step 2: Run RED**

Run: `swift test --filter HistoryStoreTests`
Expected: FAIL because app service target is not implemented.

- [ ] **Step 3: Implement services**

```swift
@MainActor final class GlobalHotKeyService {
  func register(_ hotKey: HotKey, handler: @escaping @MainActor () -> Void) throws
}

actor CaptureService {
  func capture(rect: CGRect, to outputURL: URL) async throws
  func captureFullScreen(to outputURL: URL) async throws
}
```

- [ ] **Step 4: Run GREEN and app build**

Run: `swift test --filter HistoryStoreTests && swift build`
Expected: PASS and successful build.

### Task 5: Shelf, quick actions, menu and pin panels

**Files:**
- Create: `Sources/ScreenshotApp/App/ScreenshotApp.swift`
- Create: `Sources/ScreenshotApp/App/AppDelegate.swift`
- Create: `Sources/ScreenshotApp/Models/AppModel.swift`
- Create: `Sources/ScreenshotApp/Views/ShelfView.swift`
- Create: `Sources/ScreenshotApp/Views/CaptureCardView.swift`
- Create: `Sources/ScreenshotApp/Views/MenuBarView.swift`
- Create: `Sources/ScreenshotApp/Windowing/ShelfPanelController.swift`
- Create: `Sources/ScreenshotApp/Windowing/PinnedImageController.swift`

**Interfaces:**
- Consumes: capture/history/pasteboard services.
- Produces: collapsed/expanded/temporarily-hidden shelf states and Copy, Save As, Edit, OCR, Pin, Finder, Delete commands.

- [ ] **Step 1: Write state transition tests**

```swift
@Test func newCaptureRestoresTemporarilyHiddenShelf() {
  var state = ShelfState.temporarilyHidden(until: .distantFuture)
  state.receivedNewCapture()
  #expect(state == .expanded)
}
```

- [ ] **Step 2: Run RED**

Run: `swift test --filter ShelfStateTests`
Expected: FAIL because `ShelfState` is missing.

- [ ] **Step 3: Implement state, SwiftUI shelf and narrow NSPanel controllers**

```swift
enum ShelfState: Equatable {
  case expanded, collapsed, temporarilyHidden(until: Date)
  mutating func receivedNewCapture() { self = .expanded }
}
```

- [ ] **Step 4: Run GREEN and build**

Run: `swift test --filter ShelfStateTests && swift build`
Expected: PASS.

### Task 6: Editor UI and local OCR

**Files:**
- Create: `Sources/ScreenshotApp/Views/EditorView.swift`
- Create: `Sources/ScreenshotApp/Views/EditorCanvasView.swift`
- Create: `Sources/ScreenshotApp/Views/EditorToolbarView.swift`
- Create: `Sources/ScreenshotApp/Services/OCRService.swift`
- Create: `Sources/ScreenshotApp/Windowing/EditorWindowController.swift`

**Interfaces:**
- Consumes: `EditorState`, `AnnotationRenderer`, history and pasteboard services.
- Produces: editor gestures, layer actions, save/copy and `OCRService.recognizeText(in:)`.

- [ ] **Step 1: Write OCR text-order test around an injected recognizer result**

```swift
@Test func ocrLinesAreSortedTopToBottom() {
  #expect(OCRService.join(lines: [.init(text: "два", y: 0.2), .init(text: "один", y: 0.8)]) == "один\nдва")
}
```

- [ ] **Step 2: Run RED**

Run: `swift test --filter OCRServiceTests`
Expected: FAIL because OCR helpers are missing.

- [ ] **Step 3: Implement Vision request and editor SwiftUI gestures**

```swift
actor OCRService {
  func recognizeText(in image: CGImage) async throws -> String
  static func join(lines: [RecognizedLine]) -> String
}
```

- [ ] **Step 4: Run GREEN and build**

Run: `swift test --filter OCRServiceTests && swift build`
Expected: PASS.

### Task 7: Scroll capture controller and settings

**Files:**
- Create: `Sources/ScreenshotApp/Views/ScrollCaptureControlsView.swift`
- Create: `Sources/ScreenshotApp/Windowing/ScrollCaptureController.swift`
- Create: `Sources/ScreenshotApp/Views/SettingsView.swift`

**Interfaces:**
- Consumes: region selection, `CaptureService`, `ScrollFrameClassifier`, `ScrollStitcher`, `AppPreferences`.
- Produces: automatic frame collection with Pause/Resume/Undo/Finish and editable hotkey/folder/format/history preferences.

- [ ] **Step 1: Write scroll-session tests**

```swift
@Test func undoFrameNeverRemovesTheInitialFrame() {
  var session = ScrollCaptureSession(frames: [first, second])
  session.undoLastFrame()
  session.undoLastFrame()
  #expect(session.frames.count == 1)
}
```

- [ ] **Step 2: Run RED**

Run: `swift test --filter ScrollCaptureSessionTests`
Expected: FAIL because session type is missing.

- [ ] **Step 3: Implement session, controls and settings scene**

```swift
public struct ScrollCaptureSession {
  public private(set) var frames: [CGImage]
  public mutating func add(_ frame: CGImage)
  public mutating func undoLastFrame()
  public func finish() throws -> CGImage
}
```

- [ ] **Step 4: Run GREEN and full tests**

Run: `swift test`
Expected: all tests PASS.

### Task 8: Bundle, run action and operator documentation

**Files:**
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`
- Create: `README.md`
- Create: `docs/changelog/CHANGELOG.md`

**Interfaces:**
- Produces: `dist/ScreenshotApp.app` and a reproducible Codex Run action.

- [ ] **Step 1: Add the bundle staging script with four modes**

```bash
./script/build_and_run.sh
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --verify
```

- [ ] **Step 2: Build release artifact and verify launch**

Run: `./script/build_and_run.sh --verify`
Expected: `dist/ScreenshotApp.app` exists and `pgrep -x ScreenshotApp` succeeds.

- [ ] **Step 3: Run final verification**

Run: `swift test && swift build && test -x dist/ScreenshotApp.app/Contents/MacOS/ScreenshotApp`
Expected: all commands exit 0.

- [ ] **Step 4: Record exact verified commands, permissions and known limitations in README/changelog**

Run: `rg -n "⌘⇧A|Прокрут|OCR|drag|Запись экрана" README.md docs/changelog/CHANGELOG.md`
Expected: each operator-facing feature is documented.
