# Readable Filenames and Unlimited Retention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give new captures readable local filenames based on date, time, and application name, and let users disable all automatic history deletion.

**Architecture:** Add a pure `CaptureFileName` formatter in ScreenshotCore and make the managed-file classifier accept both legacy UUID stems and new readable stems. Persist one cleanup toggle in `AppPreferences`; pass it through `AppModel` into `HistoryStore`, while `HistoryIndex` owns the enabled/disabled pruning behavior.

**Tech Stack:** Swift 5 mode, SwiftUI/AppKit, SwiftPM, UserDefaults, shell source-contract checks.

## Global Constraints

- New stem format is `21 июля, 10.32 - Telegram`; only `CaptureSource.applicationName` is used.
- Existing capture files are never renamed.
- Name collisions use ` (2)`, ` (3)`, and higher suffixes.
- Disabling automatic deletion bypasses both maximum count and maximum age.
- Manual delete and clear actions are unchanged.
- Version target is 0.5.8 build 22, Universal `arm64 + x86_64`.

---

### Task 1: Readable Managed Filenames

**Files:**
- Create: `Sources/ScreenshotCore/Formatting/CaptureFileName.swift`
- Modify: `Sources/ScreenshotCore/Stores/HistoryRetentionPolicy.swift`
- Modify: `Sources/ScreenshotApp/Services/HistoryStore.swift`
- Test: `Tests/CoreChecks/main.swift`

**Interfaces:**
- Consumes: `CaptureSource.applicationName`, capture date, folder contents.
- Produces: `CaptureFileName.baseStem(for:applicationName:calendar:locale:)`, `CaptureFileName.availableStem(baseStem:occupiedStems:)`, legacy/new classifier support.

- [ ] **Step 1: Write failing formatting and classifier checks**

Add assertions for `21 июля, 10.32 - Telegram`, a date-only fallback, sanitized `Safari Browser`, collision suffix ` (2)`, and recognition of `.png`, `.source.png`, and `.project.json` for both old and new stems.

- [ ] **Step 2: Verify RED**

Run: `swift run --disable-sandbox CoreChecks`

Expected: compile failure because `CaptureFileName` does not exist.

- [ ] **Step 3: Implement the formatter and compatibility classifier**

Create a pure formatter that uses `d MMMM, HH.mm`, normalizes application whitespace and filesystem separators, and resolves occupied stems. Update `CaptureFileClassifier.managedStem` to accept either the existing UUID regex or the new Russian readable-name regex.

- [ ] **Step 4: Use the formatter for new captures only**

In `HistoryStore.prepareCapture`, collect existing managed stems, compute a free readable stem, and keep the existing shared-stem transaction for `.png`, `.source.png`, and `.project.json`.

- [ ] **Step 5: Verify GREEN**

Run: `swift run --disable-sandbox CoreChecks && bash Tests/CaptureMetadataChecks.sh`

Expected: `CoreChecks: OK` and `CaptureMetadataChecks: OK`.

### Task 2: Optional Automatic Cleanup

**Files:**
- Modify: `Sources/ScreenshotCore/Stores/HistoryIndex.swift`
- Modify: `Sources/ScreenshotApp/Support/AppPreferences.swift`
- Modify: `Sources/ScreenshotApp/Services/HistoryStore.swift`
- Modify: `Sources/ScreenshotApp/Models/AppModel.swift`
- Modify: `Sources/ScreenshotApp/Views/SettingsView.swift`
- Modify: `Tests/CoreChecks/main.swift`
- Modify: `Tests/SettingsInteractionChecks.sh`

**Interfaces:**
- Consumes: persisted `automaticallyDeletesOldCaptures: Bool`.
- Produces: `HistoryIndex.pruned(items:automaticCleanupEnabled:maximumCount:maximumAgeDays:now:)` and a disabled-state UI for the two limits.

- [ ] **Step 1: Write failing retention and UI checks**

Add a core assertion that 25 mixed-age items remain when `automaticCleanupEnabled` is false. Require the Russian toggle text, preference key, `UserDefaults` persistence, propagation into `HistoryStore`, and `.disabled(!preferences.automaticallyDeletesOldCaptures)` in the settings contract.

- [ ] **Step 2: Verify RED**

Run: `swift run --disable-sandbox CoreChecks; bash Tests/SettingsInteractionChecks.sh`

Expected: failures because the toggle and policy parameter do not exist.

- [ ] **Step 3: Implement persistence and retention behavior**

Default `automaticallyDeletesOldCaptures` to `true`, persist it in `UserDefaults`, pass it through store initialization/update, and return all candidates sorted newest-first when automatic cleanup is disabled.

- [ ] **Step 4: Implement settings UI**

Add `Toggle("Автоматически удалять старые снимки", ...)`, keep the count/age values intact, disable both steppers while the toggle is off, and retain the existing explicit apply button.

- [ ] **Step 5: Verify GREEN**

Run: `swift run --disable-sandbox CoreChecks && bash Tests/SettingsInteractionChecks.sh`

Expected: `CoreChecks: OK` and `SettingsInteractionChecks: OK`.

### Task 3: Version, Documentation, Installation, and Release

**Files:**
- Modify: `README.md`
- Modify: `docs/changelog/CHANGELOG.md`
- Modify: `script/build_and_run.sh`
- Modify: `script/build_release.sh`
- Modify: `script/publish_release.sh`
- Modify: `.github/workflows/release.yml`
- Modify: `Tests/ReleasePackagingChecks.sh`
- Modify: `Tests/RepositoryPublicationChecks.sh`

**Interfaces:**
- Consumes: completed filename and retention behavior.
- Produces: local 0.5.8 (22), Universal archive, GitHub commit/tag/release, Sparkle appcast.

- [ ] **Step 1: Update public documentation and version contracts**

Replace current release references with `0.5.8`, build `22`, document the readable new-file format and unlimited-retention toggle, and convert the `Unreleased` changelog section into `2026-07-21 - 0.5.8`.

- [ ] **Step 2: Run complete verification**

Run all `Tests/*Checks.sh` except parameterized signing checks, then `swift build --disable-sandbox`, `swift run --disable-sandbox CoreChecks`, and `git diff --check`.

Expected: every command exits 0.

- [ ] **Step 3: Install and verify locally**

Run: `./script/build_and_run.sh --verify`

Expected: `/Users/bogdandzuba/Applications/Богдан Скриншот.app` is version `0.5.8` build `22`, signed and running.

- [ ] **Step 4: Build and validate Universal archive**

Run: `./script/build_release.sh`

Expected: archive contains `x86_64 arm64`, version `0.5.8`, build `22`, and passes `codesign --verify --deep --strict`.

- [ ] **Step 5: Commit, push, and publish**

Commit implementation, push `main`, run `./script/publish_release.sh 0.5.8`, then verify public release assets, Sparkle appcast version/build, and GitHub Actions success.
