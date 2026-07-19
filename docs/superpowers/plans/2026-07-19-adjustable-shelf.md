# Adjustable Shelf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Сделать хоткей читаемым, добавить сохраняемый вертикальный разделитель предпросмотра и истории и регулируемую прозрачность стандартного Liquid Glass.

**Architecture:** Чистая `ShelfSplitLayout` рассчитывает две высоты и ограничивает долю истории. `AppPreferences` хранит долю и прозрачность в `UserDefaults`; `ShelfView` только отображает рассчитанную геометрию и обновляет долю жестом, а `SettingsView` меняет прозрачность ползунком.

**Tech Stack:** Swift 6, SwiftUI, AppKit, SwiftPM, UserDefaults, shell regression checks.

## Global Constraints

- Минимальная версия macOS остается 14.0, системный Liquid Glass используется только через availability gate macOS 26.
- Доля истории сохраняется между изменениями размера, сворачиванием и перезапуском.
- Прозрачность меняет фон полки, но не прозрачность текста, иконок и снимков.
- Старые настройки и проекты продолжают загружаться; старым снимкам не назначается выдуманный источник.
- Любая правка проекта сопровождается обновлением `docs/changelog/CHANGELOG.md`.

---

### Task 1: Чистая геометрия разделителя

**Files:**
- Create: `Sources/ScreenshotCore/Layout/ShelfSplitLayout.swift`
- Modify: `Tests/CoreChecks/main.swift`

**Interfaces:**
- Produces: `ShelfSplitLayout.historyFraction(_:minimum:maximum:) -> Double`.
- Produces: `ShelfSplitLayout.heights(availableHeight:historyFraction:dividerHeight:latestMinimumHeight:historyMinimumHeight:) -> (latest: CGFloat, history: CGFloat)`.

- [x] **Step 1: Write the failing test**

```swift
try expect(ShelfSplitLayout.historyFraction(-1) == 0.2, "history fraction clamps low")
try expect(ShelfSplitLayout.historyFraction(2) == 0.65, "history fraction clamps high")
let split = ShelfSplitLayout.heights(availableHeight: 500, historyFraction: 0.3)
try expect(split.latest + split.history + ShelfSplitLayout.dividerHeight == 500, "split uses all height")
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift run CoreChecks`
Expected: FAIL to compile because `ShelfSplitLayout` is missing.

- [x] **Step 3: Write minimal implementation**

```swift
public enum ShelfSplitLayout {
    public static let minimumHistoryFraction = 0.2
    public static let maximumHistoryFraction = 0.65
    public static let defaultHistoryFraction = 0.3
    public static let dividerHeight: CGFloat = 10

    public static func historyFraction(_ value: Double) -> Double {
        min(max(value, minimumHistoryFraction), maximumHistoryFraction)
    }
}
```

Add the deterministic height calculation with minimums of 140 pt for the latest section and 80 pt for history.

- [x] **Step 4: Run test to verify it passes**

Run: `swift run CoreChecks`
Expected: `CoreChecks: OK`.

### Task 2: Persistent preferences and settings

**Files:**
- Modify: `Sources/ScreenshotApp/Support/AppPreferences.swift`
- Modify: `Sources/ScreenshotApp/Views/SettingsView.swift`
- Modify: `Tests/SettingsInteractionChecks.sh`

**Interfaces:**
- Consumes: `ShelfSplitLayout.historyFraction(_:)`.
- Produces: `AppPreferences.historyFraction: Double` and `AppPreferences.shelfTransparency: Double` in `0...1`.

- [x] **Step 1: Write the failing UI contract**

Require `Slider(value: $preferences.shelfTransparency, in: 0...1)` and persisted keys `historyFraction` and `shelfTransparency` in `Tests/SettingsInteractionChecks.sh`.

- [x] **Step 2: Run test to verify it fails**

Run: `bash Tests/SettingsInteractionChecks.sh`
Expected: FAIL because the new preferences and slider are missing.

- [x] **Step 3: Implement preferences and setting**

```swift
@Published var historyFraction: Double {
    didSet {
        let value = ShelfSplitLayout.historyFraction(historyFraction)
        if value != historyFraction { historyFraction = value; return }
        defaults.set(value, forKey: Key.historyFraction)
    }
}

@Published var shelfTransparency: Double {
    didSet {
        let value = min(max(shelfTransparency, 0), 1)
        if value != shelfTransparency { shelfTransparency = value; return }
        defaults.set(value, forKey: Key.shelfTransparency)
    }
}
```

Add a `Внешний вид` section with the percentage label and slider. Default transparency is 35%.

- [x] **Step 4: Run test to verify it passes**

Run: `bash Tests/SettingsInteractionChecks.sh`
Expected: `SettingsInteractionChecks: OK`.

### Task 3: Adjustable shelf UI

**Files:**
- Modify: `Sources/ScreenshotApp/Views/ShelfView.swift`
- Modify: `Sources/ScreenshotCore/Layout/ShelfMetrics.swift`
- Modify: `Tests/ShelfPanelInteractionChecks.sh`

**Interfaces:**
- Consumes: `preferences.historyFraction`, `preferences.shelfTransparency` and `ShelfSplitLayout.heights(...)`.
- Produces: a full-width `ShelfSplitDivider` drag target with `resizeUpDown` cursor behavior.

- [x] **Step 1: Write the failing UI contract**

Require a 13 pt semibold hotkey, `GeometryReader`, `ShelfSplitLayout.heights`, `DragGesture`, `historyFraction`, `shelfTransparency`, and standard `.glassEffect(.regular, in: shape)`. Reject the old 144 pt maximum and `.glassEffect(.clear, in: shape)`.

- [x] **Step 2: Run test to verify it fails**

Run: `bash Tests/ShelfPanelInteractionChecks.sh`
Expected: FAIL on the first missing adjustable-split contract.

- [x] **Step 3: Implement the split and glass**

```swift
GeometryReader { proxy in
    let split = ShelfSplitLayout.heights(
        availableHeight: proxy.size.height,
        historyFraction: preferences.historyFraction
    )
    VStack(spacing: 0) {
        latest(item).frame(height: split.latest)
        splitDivider(availableHeight: proxy.size.height)
        historyList(selected: item).frame(height: split.history)
    }
}
```

During drag, convert vertical translation back to a clamped history fraction and persist it. Use standard system glass and a background tint whose alpha decreases as transparency increases; never apply `.opacity` to the entire content.

- [x] **Step 4: Run targeted checks**

Run: `swift run CoreChecks`
Expected: `CoreChecks: OK`.

Run: `bash Tests/ShelfPanelInteractionChecks.sh`
Expected: `ShelfPanelInteractionChecks: OK`.

Run: `bash Tests/SettingsInteractionChecks.sh`
Expected: `SettingsInteractionChecks: OK`.

### Task 4: Documentation, build and installed app proof

**Files:**
- Modify: `docs/changelog/CHANGELOG.md`
- Modify: `script/build_and_run.sh`
- Modify: `script/build_release.sh`
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Produces: local app version 0.5.1 build 15 and a fresh local ZIP.

- [x] **Step 1: Record the shipped behavior and bump version**

Add a `0.5.1` changelog section and set local/release defaults to version `0.5.1`, build `15`; set the workflow fallback version to `0.5.1`.

- [x] **Step 2: Run the full installed-app verification**

Run: `./script/build_and_run.sh --verify`
Expected: all checks end in `OK`, codesign verification succeeds, and `ScreenshotApp` is running.

- [x] **Step 3: Verify artifacts**

Run: `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '/Users/bogdandzuba/Applications/ScreenshotApp Bogdan.app/Contents/Info.plist'`
Expected: `0.5.1`.

Run: `/usr/bin/codesign --verify --deep --strict '/Users/bogdandzuba/Applications/ScreenshotApp Bogdan.app'`
Expected: exit 0.

- [x] **Step 4: Review and commit**

Run: `git diff --check`
Expected: exit 0.

Commit the implementation and verification updates with a concise Russian message.
