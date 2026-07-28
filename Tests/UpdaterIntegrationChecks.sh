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
require_text Sources/ScreenshotApp/Services/UpdateService.swift 'AutomaticUpdateDefaultsMigration.shouldEnableAutomaticUpdates' \
  "existing installations are not migrated to automatic updates"
require_text Sources/ScreenshotApp/Services/UpdateService.swift 'willInstallUpdateOnQuit' \
  "downloaded updates are not installed immediately"
require_text Sources/ScreenshotApp/Services/UpdateService.swift 'immediateInstallHandler()' \
  "automatic updates do not trigger Sparkle's silent install and relaunch"
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
require_text script/build_release.sh 'SUAutomaticallyUpdate -bool YES' \
  "release bundle does not enable automatic install by default"
require_text script/build_release.sh 'SUScheduledCheckInterval -integer 86400' \
  "release bundle does not use a one-day polling interval"
require_text script/build_and_run.sh 'SUAutomaticallyUpdate' \
  "local bundle does not declare the automatic-download default"
require_text script/build_and_run.sh '<integer>86400</integer>' \
  "local bundle does not use a one-day polling interval"
require_text Sources/ScreenshotApp/Views/SettingsView.swift 'раз в сутки' \
  "settings do not explain the daily automatic update behavior"
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

TEMP_DIR="$(mktemp -d /private/tmp/ScreenshotAppUpdaterIntegration.XXXXXX)"
cleanup() {
  /bin/rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

PUBLISH_ROOT="$TEMP_DIR/project"
FAKE_BIN="$TEMP_DIR/bin"
/bin/mkdir -p "$PUBLISH_ROOT/script" "$FAKE_BIN"
/bin/cp script/publish_release.sh "$PUBLISH_ROOT/script/publish_release.sh"

/bin/cat >"$PUBLISH_ROOT/script/version.sh" <<'SH'
SCREENSHOT_APP_CURRENT_VERSION="0.5.25"
SCREENSHOT_APP_CURRENT_BUILD_NUMBER="39"
SH

/bin/cat >"$PUBLISH_ROOT/script/next_release_build_number.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >"${SCREENSHOT_APP_TEST_CANDIDATE_LOG:?}"
printf '%s\n' "$2" >"${SCREENSHOT_APP_TEST_APPCAST_LOG:?}"
printf '%s\n' "$1"
SH

/bin/cat >"$PUBLISH_ROOT/script/build_release.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${SCREENSHOT_APP_BUILD_NUMBER:-}" >"${SCREENSHOT_APP_TEST_BUILD_LOG:?}"
exit 86
SH

/bin/cat >"$FAKE_BIN/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "branch --show-current")
    printf '%s\n' "main"
    ;;
  "status --porcelain"|"fetch origin main")
    exit 0
    ;;
  "rev-parse HEAD"|"rev-parse origin/main")
    printf '%s\n' "0123456789abcdef"
    ;;
  "rev-list --count HEAD")
    printf '%s\n' "32"
    ;;
  *)
    echo "unexpected git invocation: $*" >&2
    exit 97
    ;;
esac
SH

/bin/cat >"$FAKE_BIN/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "auth status --hostname github.com" ]]; then
  exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 97
SH

/bin/chmod +x \
  "$PUBLISH_ROOT/script/publish_release.sh" \
  "$PUBLISH_ROOT/script/next_release_build_number.sh" \
  "$PUBLISH_ROOT/script/build_release.sh" \
  "$FAKE_BIN/git" \
  "$FAKE_BIN/gh"

PUBLIC_APPCAST_URL="https://github.com/bogdan0dzuba/screenshotapp-bogdan/releases/latest/download/appcast.xml"
CANDIDATE_LOG="$TEMP_DIR/candidate.log"
APPCAST_LOG="$TEMP_DIR/appcast.log"
BUILD_LOG="$TEMP_DIR/build.log"

run_publish_wiring_case() {
  local expected_candidate="$1"
  local supplied_candidate="$2"
  local output_file="$TEMP_DIR/publish-$expected_candidate.log"
  local status

  /bin/rm -f -- "$CANDIDATE_LOG" "$APPCAST_LOG" "$BUILD_LOG"
  if PATH="$FAKE_BIN:$PATH" \
    SCREENSHOT_APP_BUILD_NUMBER="$supplied_candidate" \
    SCREENSHOT_APP_TEST_CANDIDATE_LOG="$CANDIDATE_LOG" \
    SCREENSHOT_APP_TEST_APPCAST_LOG="$APPCAST_LOG" \
    SCREENSHOT_APP_TEST_BUILD_LOG="$BUILD_LOG" \
    /bin/bash "$PUBLISH_ROOT/script/publish_release.sh" 0.5.25 \
    >"$output_file" 2>&1; then
    status=0
  else
    status=$?
  fi

  if [[ "$status" -ne 86 ]]; then
    /bin/cat "$output_file" >&2
    echo "UpdaterIntegrationChecks: publish wiring did not reach the controlled build boundary" >&2
    exit 1
  fi
  if [[ ! -f "$CANDIDATE_LOG" || "$(<"$CANDIDATE_LOG")" != "$expected_candidate" ]]; then
    echo "UpdaterIntegrationChecks: release candidate was not validated" >&2
    exit 1
  fi
  if [[ ! -f "$APPCAST_LOG" || "$(<"$APPCAST_LOG")" != "$PUBLIC_APPCAST_URL" ]]; then
    echo "UpdaterIntegrationChecks: release candidate was not compared with the public appcast" >&2
    exit 1
  fi
  if [[ ! -f "$BUILD_LOG" || "$(<"$BUILD_LOG")" != "$expected_candidate" ]]; then
    echo "UpdaterIntegrationChecks: validated release build was not passed to packaging" >&2
    exit 1
  fi
}

run_publish_wiring_case "39" ""
run_publish_wiring_case "45" "45"

echo "UpdaterIntegrationChecks: OK"
