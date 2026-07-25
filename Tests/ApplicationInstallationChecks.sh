#!/usr/bin/env bash
set -euo pipefail

DELEGATE="${1:-Sources/ScreenshotApp/App/AppDelegate.swift}"
COORDINATOR="${2:-Sources/ScreenshotApp/Services/ApplicationInstallationCoordinator.swift}"
LOCAL_BUILD="${3:-script/build_and_run.sh}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if [[ ! -f "$file" ]] || ! /usr/bin/grep -Fq -- "$pattern" "$file"; then
    echo "ApplicationInstallationChecks: $failure" >&2
    exit 1
  fi
}

require_text "$DELEGATE" "offerInstallationIfNeeded" \
  "first launch does not offer to install an app opened from Downloads"
require_text "$COORDINATOR" 'messageText = "Установить «Богдан Скриншот»?"' \
  "installation prompt is not clear"
require_text "$COORDINATOR" 'checkboxWithTitle: "После установки переместить скачанную копию в Корзину"' \
  "source cleanup is not explicitly controlled by the user"
require_text "$COORDINATOR" "ApplicationBundleInstaller.install" \
  "accepted installation does not copy the bundle into Applications"
require_text "$COORDINATOR" "FileManager.default.trashItem" \
  "approved downloaded source is not moved to Trash"
require_text "$COORDINATOR" "openApplication(at:" \
  "installed copy is not launched after installation"
require_text "$COORDINATOR" "NSApp.terminate(nil)" \
  "temporary downloaded process remains running after installation"
require_text "$LOCAL_BUILD" 'trap cleanup_stage EXIT' \
  "local build leaves temporary app bundles discoverable by LaunchServices"
require_text "$LOCAL_BUILD" 'unregister_bundle "$APP_BUNDLE"' \
  "local build does not unregister its staged app bundle"
require_text "$LOCAL_BUILD" 'unregister_bundle "$LEGACY_INSTALLED_APP"' \
  "legacy app registration can remain as a duplicate search result"
require_text "$LOCAL_BUILD" "unregister_trash_duplicates" \
  "backup app bundles in Trash can remain visible as duplicate search results"

echo "ApplicationInstallationChecks: OK"
