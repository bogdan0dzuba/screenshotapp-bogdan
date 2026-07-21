#!/usr/bin/env bash
set -euo pipefail

require_text() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if [[ ! -f "$file" ]] || ! /usr/bin/grep -Fq -- "$pattern" "$file"; then
    echo "UpdaterIntegrationChecks: $message" >&2
    exit 1
  fi
}

require_text Package.swift 'sparkle-project/Sparkle' "Sparkle package is not configured"
require_text Sources/ScreenshotApp/Services/UpdateService.swift 'SPUStandardUpdaterController' \
  "standard Sparkle updater is not initialized"
require_text Sources/ScreenshotApp/Services/UpdateService.swift 'startingUpdater: false' \
  "Sparkle starts before the app can schedule a deterministic launch check"
require_text Sources/ScreenshotApp/Services/UpdateService.swift 'startUpdaterAndCheckAtLaunch()' \
  "updater has no explicit launch check entry point"
require_text Sources/ScreenshotApp/Services/UpdateService.swift 'updaterController.startUpdater()' \
  "launch check does not start Sparkle at application launch"
require_text Sources/ScreenshotApp/Services/UpdateService.swift 'updaterController.updater.checkForUpdatesInBackground()' \
  "launch check does not query the signed appcast in the background"
require_text Sources/ScreenshotApp/Services/UpdateService.swift 'standardUserDriverWillShowModalAlert()' \
  "scheduled update alerts are not brought forward for the menu bar app"
require_text Sources/ScreenshotApp/Services/UpdateService.swift 'NSApp.activate(ignoringOtherApps: true)' \
  "scheduled update popup can remain hidden behind other applications"
require_text Sources/ScreenshotApp/App/AppDelegate.swift 'updateService.startUpdaterAndCheckAtLaunch()' \
  "application launch does not start the updater and check the appcast"
require_text Sources/ScreenshotApp/Views/MenuBarView.swift 'updateService.checkForUpdates()' \
  "manual update action is not connected to Sparkle"
require_text Sources/ScreenshotApp/Views/SettingsView.swift 'Автоматически проверять обновления' \
  "automatic update setting is missing"
require_text script/build_release.sh 'SUFeedURL' "release bundle has no appcast URL"
require_text script/build_release.sh 'SUPublicEDKey' "release bundle has no EdDSA public key"
require_text script/build_release.sh 'SUAutomaticallyUpdate -bool NO' \
  "release bundle does not default to a visible user-confirmed update"
require_text script/build_release.sh 'SUScheduledCheckInterval -integer 21600' \
  "release bundle does not shorten Sparkle's one-day polling interval"
require_text script/build_and_run.sh 'SUAutomaticallyUpdate' \
  "local bundle does not declare the automatic-download default"
require_text script/build_and_run.sh '<integer>21600</integer>' \
  "local bundle does not shorten Sparkle's one-day polling interval"
require_text script/publish_release.sh 'generate_keys' \
  "local release script does not read the Sparkle key from macOS Keychain"
require_text script/publish_release.sh 'generate_appcast' \
  "local release script does not sign the update feed"
require_text script/publish_release.sh 'ScreenshotApp-Bogdan-release-arm64-$(id -u)/artifacts/sparkle/Sparkle/bin' \
  "fresh-clone release cannot find Sparkle tools in the architecture scratch build"
require_text script/publish_release.sh 'APPCAST_INPUT_DIR' \
  "appcast generation is not isolated from stale local archives"
require_text script/publish_release.sh 'gh release create' \
  "local release script does not publish GitHub release assets"

if /usr/bin/grep -Fq -- 'SPARKLE_PRIVATE_KEY' .github/workflows/release.yml; then
  echo "UpdaterIntegrationChecks: Sparkle private key must remain on the release Mac" >&2
  exit 1
fi

if /usr/bin/grep -Fq -- 'runs-on: macos-15-intel' .github/workflows/release.yml; then
  echo "UpdaterIntegrationChecks: Intel runner reproducibly kills CoreChecks after linking" >&2
  exit 1
fi
require_text .github/workflows/release.yml 'swift build --disable-sandbox --product CoreChecks' \
  "CI does not build CoreChecks in an isolated SwiftPM process"
require_text .github/workflows/release.yml '.build/debug/CoreChecks' \
  "CI does not execute the already-built CoreChecks binary"

echo "UpdaterIntegrationChecks: OK"
