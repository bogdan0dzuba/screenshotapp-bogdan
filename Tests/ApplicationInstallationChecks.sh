#!/usr/bin/env bash
set -euo pipefail

DELEGATE="${1:-Sources/ScreenshotApp/App/AppDelegate.swift}"
COORDINATOR="${2:-Sources/ScreenshotApp/Services/ApplicationInstallationCoordinator.swift}"

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

echo "ApplicationInstallationChecks: OK"
