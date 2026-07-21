#!/usr/bin/env bash
set -euo pipefail

CONTROLLER="${1:-Sources/ScreenshotApp/Windowing/SettingsWindowController.swift}"
APP_DELEGATE="${2:-Sources/ScreenshotApp/App/AppDelegate.swift}"
SHELF_CONTROLLER="${3:-Sources/ScreenshotApp/Windowing/ShelfPanelController.swift}"
SHELF_VIEW="${4:-Sources/ScreenshotApp/Views/ShelfView.swift}"
MENU_VIEW="${5:-Sources/ScreenshotApp/Views/MenuBarView.swift}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if [[ ! -f "$file" ]] || ! /usr/bin/grep -Fq -- "$pattern" "$file"; then
    echo "SettingsWindowChecks: $failure" >&2
    exit 1
  fi
}

require_text "$CONTROLLER" 'final class SettingsWindowController' \
  "settings have no window owner outside the SwiftUI scene environment"
require_text "$CONTROLLER" 'func show()' "settings window cannot be shown repeatedly"
require_text "$CONTROLLER" 'NSApp.activate(ignoringOtherApps: true)' \
  "settings window can remain behind other apps"
require_text "$APP_DELEGATE" 'settingsController = SettingsWindowController(' \
  "application delegate does not retain the settings window"
require_text "$APP_DELEGATE" 'func showSettings()' \
  "shelf and menu cannot share one settings action"
require_text "$SHELF_CONTROLLER" 'onOpenSettings: @escaping () -> Void' \
  "custom shelf panel does not receive an explicit settings callback"
require_text "$SHELF_VIEW" 'Button(action: onOpenSettings)' \
  "shelf gear still relies on a missing SwiftUI scene environment"
require_text "$MENU_VIEW" 'Button("Настройки…", action: onOpenSettings)' \
  "menu and shelf do not open the same settings window"

echo "SettingsWindowChecks: OK"
