# Startup, Update, and Delivery Blockers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the recurring duplicate-app source, enable launch at login through macOS, and guarantee monotonically increasing Sparkle build numbers.

**Architecture:** Keep deterministic policies in `ScreenshotCore`, bridge login-item state to `SMAppService.mainApp` in one app service, and make release build-number selection a standalone executable shell contract. Distribution trust remains explicitly gated on real Apple Developer ID and notarization credentials.

**Tech Stack:** Swift 5 language mode, SwiftUI/AppKit, ServiceManagement, SwiftPM CoreChecks, Bash, Sparkle 2.9.4.

## Global Constraints

- Minimum macOS version remains 14.0.
- Only the exact downloaded source bundle approved by the user may be deleted.
- Login-item UI reflects actual `SMAppService.Status`.
- `CFBundleVersion` must be strictly greater than the latest public `sparkle:version`.
- Existing dirty workspace changes must be preserved.
- Every project-file change is recorded in `docs/changelog/CHANGELOG.md`.

---

### Task 1: Source Bundle Cleanup

**Files:**
- Modify: `Sources/ScreenshotCore/Installation/ApplicationInstallPolicy.swift`
- Modify: `Sources/ScreenshotApp/Services/ApplicationInstallationCoordinator.swift`
- Modify: `Tests/CoreChecks/main.swift`
- Modify: `Tests/ApplicationInstallationChecks.sh`

**Interfaces:**
- Consumes: source URL, installed URL, explicit cleanup consent, successful launch.
- Produces: `ApplicationInstallPolicy.cleanupCandidate(...)` and irreversible deletion of only that returned URL.

- [x] **Step 1: Write the failing behavior checks**

Add a CoreChecks case proving no cleanup candidate is returned without consent or for the installed bundle, and a shell integration check that requires `removeItem(at:)` while rejecting `trashItem`.

- [x] **Step 2: Verify RED**

Run: `swift run --disable-sandbox CoreChecks && bash Tests/ApplicationInstallationChecks.sh`

Expected: `ApplicationInstallationChecks` fails because the coordinator still calls `trashItem`.

- [x] **Step 3: Implement minimal cleanup**

Change the checkbox copy to `После установки удалить скачанную копию`, delete only the policy-approved source after the installed app opens successfully, and surface a warning if deletion fails.

- [x] **Step 4: Verify GREEN**

Run: `swift run --disable-sandbox CoreChecks && bash Tests/ApplicationInstallationChecks.sh`

Expected: both commands exit 0.

### Task 2: Launch at Login

**Files:**
- Create: `Sources/ScreenshotCore/Startup/LaunchAtLoginPolicy.swift`
- Create: `Sources/ScreenshotApp/Services/LaunchAtLoginService.swift`
- Modify: `Sources/ScreenshotApp/App/AppDelegate.swift`
- Modify: `Sources/ScreenshotApp/Windowing/SettingsWindowController.swift`
- Modify: `Sources/ScreenshotApp/Views/SettingsView.swift`
- Modify: `Tests/CoreChecks/main.swift`
- Modify: `Tests/SettingsInteractionChecks.sh`
- Modify: `Tests/SettingsWindowChecks.sh`

**Interfaces:**
- Consumes: normalized status `notRegistered`, `enabled`, `requiresApproval`, or `notFound`.
- Produces: policy actions `register`, `unregister`, or `none`; one app-owned observable service backed by `SMAppService.mainApp`.

- [x] **Step 1: Write failing policy and wiring checks**

Add literal CoreChecks expectations for all desired-state/status pairs and settings checks for the Russian toggle, service injection, registration, unregistering, and the system-settings action.

- [x] **Step 2: Verify RED**

Run: `swift run --disable-sandbox CoreChecks; bash Tests/SettingsInteractionChecks.sh; bash Tests/SettingsWindowChecks.sh`

Expected: failures because launch-at-login policy and service do not exist.

- [x] **Step 3: Implement the policy and service**

Map actual `SMAppService.Status` into the pure policy, treating initial `notFound` as a registration action, call `register()` or `unregister()`, refresh from the actual status after every operation, persist the one-time marker only after success, and expose an actionable Russian status message plus diagnostic logging.

- [x] **Step 4: Wire settings and startup**

Own one service in `AppDelegate`, pass it through `SettingsWindowController`, call the one-time enablement after installation gating, and add the toggle to the existing updates section.

- [x] **Step 5: Verify GREEN**

Run: `swift run --disable-sandbox CoreChecks && bash Tests/SettingsInteractionChecks.sh && bash Tests/SettingsWindowChecks.sh`

Expected: all commands exit 0.

### Task 3: Monotonic Sparkle Build Number

**Files:**
- Create: `script/next_release_build_number.sh`
- Create: `Tests/ReleaseBuildNumberChecks.sh`
- Modify: `script/publish_release.sh`
- Modify: `Tests/UpdaterIntegrationChecks.sh`
- Modify: `script/build_release.sh`

**Interfaces:**
- Consumes: candidate build number and an appcast file or URL.
- Produces: validated numeric build number strictly greater than public `sparkle:version`.

- [x] **Step 1: Write an executable failing test**

Create fixture appcasts with build 31 and assert candidate 32 succeeds while 31, 30, empty, and nonnumeric candidates fail.

- [x] **Step 2: Verify RED**

Run: `bash Tests/ReleaseBuildNumberChecks.sh`

Expected: failure because `script/next_release_build_number.sh` does not exist.

- [x] **Step 3: Implement build-number validation**

Parse the first appcast item's `sparkle:version` with `xmllint`, validate numeric inputs, and print the accepted candidate only when it is greater.

- [x] **Step 4: Wire publication**

Use `SCREENSHOT_APP_BUILD_NUMBER` when supplied, otherwise the shared build number from `script/version.sh`; download the latest public appcast, validate the candidate, and pass it to `build_release.sh`.

- [x] **Step 5: Verify GREEN**

Run: `bash Tests/ReleaseBuildNumberChecks.sh && bash Tests/UpdaterIntegrationChecks.sh`

Expected: both commands exit 0.

### Task 4: Documentation, Installation, and Delivery Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/changelog/CHANGELOG.md`
- Modify: `script/build_and_run.sh`
- Modify: `Tests/AppIdentityChecks.sh`

**Interfaces:**
- Consumes: completed cleanup, login item, and build-number behavior.
- Produces: installed local bundle, copy-ready ZIP, and an explicit Developer ID/notarization boundary.

- [x] **Step 1: Update version and delivery documentation**

Document launch at login, permanent source cleanup wording, automatic build-number validation, and the exact external Gatekeeper requirements. Add one unreleased changelog entry covering all three fixes.

- [x] **Step 2: Run focused and full verification**

Run: `swift run --disable-sandbox CoreChecks`, every applicable `Tests/*Checks.sh`, `swift build --disable-sandbox --product ScreenshotApp`, and `git diff --check`.

Expected: all applicable commands exit 0 with no new warnings.

- [x] **Step 3: Install and verify locally**

Run: `bash script/build_and_run.sh --verify`.

Expected: the installed app launches, reports the new version, and only `/Users/bogdandzuba/Applications/Богдан Скриншот.app` remains as a physical bundle with identifier `local.codex.ScreenshotApp`.

- [x] **Step 4: Verify login-item state**

Read `SMAppService.mainApp.status` through the built service or `sfltool dumpbtm`; accept only `enabled` or an explicitly reported `requiresApproval`.

- [x] **Step 5: Verify release boundary**

Run the local Universal packaging checks if the signing identity exists. Otherwise record the exact missing identity/profile and do not claim Gatekeeper or notarization success.
