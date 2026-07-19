# Capture Metadata and Compact Shelf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить локальные метаданные источника снимка и переработать полку так, чтобы основную площадь занимало изображение.

**Architecture:** `ScreenshotCore` владеет Codable-моделью и чистым форматированием. Узкий AppKit-сервис получает активное приложение и заголовок окна без новых разрешений, `AppModel` передает снимок источника в `HistoryStore`, а существующий JSON-проект сохраняет его между запусками. `ShelfView` только отображает готовые метаданные и компактный chrome.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Core Graphics, SwiftPM, shell contract checks, macOS 14+ с Liquid Glass на macOS 26.

## Global Constraints

- Никаких AppleScript, Accessibility, Automation, сети или новых системных разрешений.
- Старые `*.project.json` обязаны декодироваться.
- Физические имена управляемых файлов не меняются.
- Все новые пользовательские строки - на русском.
- Реализация идет RED -> GREEN, затем targeted и полная установленная сборка.

---

### Task 1: Модель источника и форматирование

**Files:**
- Create: `Sources/ScreenshotCore/Models/CaptureSource.swift`
- Modify: `Sources/ScreenshotCore/Models/CaptureItem.swift`
- Modify: `Sources/ScreenshotCore/Models/EditorDocument.swift`
- Modify: `Sources/ScreenshotCore/Formatting/CaptureTimestampFormatter.swift`
- Test: `Tests/CoreChecks/main.swift`

**Interfaces:**
- Produces: `CaptureSource(applicationName:windowTitle:)`, `CaptureSource.displayLabel`, `CaptureTimestampFormatter.historyTitle(for:calendar:locale:)`.

- [ ] **Step 1: Write failing CoreChecks** for decoding an old project, source JSON round-trip, URL/domain cleanup, title fallback and `19 июля, 14:50` formatting.
- [ ] **Step 2: Run RED:** `swift run --disable-sandbox CoreChecks`; expected compile failure because `CaptureSource` and `historyTitle` do not exist.
- [ ] **Step 3: Implement minimal optional fields and pure formatters.** Optional fields use default `nil`; display text trims whitespace, removes duplicate browser suffixes and shortens explicit URLs to a host.
- [ ] **Step 4: Run GREEN:** `swift run --disable-sandbox CoreChecks`; expected `CoreChecks: OK`.

### Task 2: Сбор и сохранение источника

**Files:**
- Create: `Sources/ScreenshotApp/Services/CaptureSourceProvider.swift`
- Modify: `Sources/ScreenshotApp/Models/AppModel.swift`
- Modify: `Sources/ScreenshotApp/Services/HistoryStore.swift`
- Create: `Tests/CaptureMetadataChecks.sh`

**Interfaces:**
- Consumes: `CaptureSource`.
- Produces: `CaptureSourceProvider.current() -> CaptureSource?`, `HistoryStore.importCapture(at:source:)`, `HistoryStore.importImage(_:source:)`.

- [ ] **Step 1: Write the failing integration contract.** Require source collection before `suspend()`, propagation through both capture modes, JSON persistence and reload; reject `AppleScript`, `AXUIElement` and automation events.
- [ ] **Step 2: Run RED:** `bash Tests/CaptureMetadataChecks.sh`; expected failure because the provider is missing.
- [ ] **Step 3: Implement the provider and propagation.** Prefer the frontmost non-owning app, select its first layer-zero on-screen window, and fall back to the first visible non-owning window or app name. Store a pending source only while scrolling capture is active.
- [ ] **Step 4: Run GREEN:** `bash Tests/CaptureMetadataChecks.sh` and `swift run --disable-sandbox CoreChecks`; both expected OK.

### Task 3: Компактная прозрачная полка

**Files:**
- Modify: `Sources/ScreenshotApp/Views/ShelfView.swift`
- Modify: `Sources/ScreenshotCore/Layout/ShelfMetrics.swift`
- Modify: `Tests/ShelfPanelInteractionChecks.sh`
- Modify: `Tests/CoreChecks/main.swift`

**Interfaces:**
- Consumes: `CaptureItem.captureSource`, `CaptureTimestampFormatter.historyTitle`, `AppModel.hotKeyDescription`.
- Produces: prominent count/hotkey header, icon-only 28 pt quick actions, 30 pt capture bar, compact metadata rows, Clear Liquid Glass.

- [ ] **Step 1: Tighten failing UI contracts.** Reject `Label("Скриншоты"`, quick-action text and labeled scrolling capture; require the count, hotkey, icon-only controls, compact metrics, source/date rows and clear glass.
- [ ] **Step 2: Run RED:** `bash Tests/ShelfPanelInteractionChecks.sh` and `swift run --disable-sandbox CoreChecks`; expected failures against the current shelf.
- [ ] **Step 3: Implement the compact view.** Preserve compact status feedback, hit targets, context menus, drag-and-drop, copy-on-click and pinch while reducing chrome.
- [ ] **Step 4: Run GREEN:** both targeted checks expected OK.

### Task 4: Changelog, installed build and release artifact

**Files:**
- Modify: `docs/changelog/CHANGELOG.md`
- Regenerate: `dist/ScreenshotApp-Bogdan-macOS-Universal.zip`

**Interfaces:**
- Produces: installed `ScreenshotApp Bogdan.app` version 0.5.0 build 14 and fresh Universal ZIP containing the new code.

- [ ] **Step 1: Run all shell contracts** including editor, settings, signing, repository and release packaging checks.
- [ ] **Step 2: Run `./script/build_and_run.sh --verify`** and verify the installed version, signature and running process.
- [ ] **Step 3: Run `./script/build_release.sh`** and verify `lipo -archs` reports `x86_64 arm64`.
- [ ] **Step 4: Inspect the diff and changelog** for personal paths, secrets, placeholders and unintended file-name changes.
