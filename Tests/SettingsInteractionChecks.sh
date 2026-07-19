#!/usr/bin/env bash
set -euo pipefail

SETTINGS_VIEW="${1:-Sources/ScreenshotApp/Views/SettingsView.swift}"
APP_MODEL="${2:-Sources/ScreenshotApp/Models/AppModel.swift}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if ! /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "SettingsInteractionChecks: $failure" >&2
    exit 1
  fi
}

require_text "$SETTINGS_VIEW" 'Toggle("Command (⌘)"' "Command modifier is shown as an unexplained symbol"
require_text "$SETTINGS_VIEW" 'Toggle("Shift (⇧)"' "Shift modifier is shown as an unexplained symbol"
require_text "$SETTINGS_VIEW" 'Toggle("Option (⌥)"' "Option modifier is shown as an unexplained symbol"
require_text "$SETTINGS_VIEW" 'Toggle("Control (⌃)"' "Control modifier is shown as an unexplained symbol"
require_text "$SETTINGS_VIEW" ".toggleStyle(.checkbox)" "modifier controls still look like unrelated switches"
require_text "$SETTINGS_VIEW" 'LabeledContent("Текущая комбинация")' "current shortcut has no clear label"
require_text "$SETTINGS_VIEW" "model.hotKeyReadableDescription" "settings do not show the readable shortcut"
require_text "$SETTINGS_VIEW" 'Picker("Клавиша"' "letter selector has no visible label"
require_text "$APP_MODEL" "HotKeyDisplayFormatter.symbolic" "compact shortcut formatting remains hand-written"
require_text "$APP_MODEL" "HotKeyDisplayFormatter.readable" "readable shortcut formatting is missing"

echo "SettingsInteractionChecks: OK"
