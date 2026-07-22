#!/usr/bin/env bash
set -euo pipefail

SETTINGS_VIEW="${1:-Sources/ScreenshotApp/Views/SettingsView.swift}"
APPLICATION="${2:-Sources/ScreenshotApp/App/ScreenshotApplication.swift}"
LOCAL_BUILD="${3:-script/build_and_run.sh}"
RELEASE_BUILD="${4:-script/build_release.sh}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if [[ ! -f "$file" ]] || ! /usr/bin/grep -Fq -- "$pattern" "$file"; then
    echo "AppIdentityChecks: $failure" >&2
    exit 1
  fi
}

require_text Sources/ScreenshotApp/Support/AppIdentity.swift 'displayName = "Богдан Скриншот"' \
  "the public product name is missing"
if /usr/bin/grep -Fq -- 'CFBundleVersion' Sources/ScreenshotApp/Support/AppIdentity.swift; then
  echo "AppIdentityChecks: the internal build number is exposed to users" >&2
  exit 1
fi
require_text "$APPLICATION" 'MenuBarExtra(AppIdentity.displayName' \
  "menu bar app does not use the public product name"
require_text "$SETTINGS_VIEW" 'Section("О приложении")' \
  "settings do not show an about section"
require_text "$SETTINGS_VIEW" 'AppIdentity.versionDescription' \
  "settings do not show the installed bundle version"
require_text "$LOCAL_BUILD" 'APP_NAME="Богдан Скриншот"' \
  "local app bundle still uses the old name"
require_text "$RELEASE_BUILD" 'APP_NAME="Богдан Скриншот"' \
  "release app bundle still uses the old name"
require_text "$LOCAL_BUILD" 'CFBundleIconFile' \
  "local app bundle does not declare an icon"
require_text "$RELEASE_BUILD" 'CFBundleIconFile' \
  "release app bundle does not declare an icon"
[[ -s Assets/AppIcon.icns ]] || {
  echo "AppIdentityChecks: AppIcon.icns is missing" >&2
  exit 1
}

echo "AppIdentityChecks: OK"
