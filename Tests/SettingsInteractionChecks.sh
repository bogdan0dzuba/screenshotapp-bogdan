#!/usr/bin/env bash
set -euo pipefail

SETTINGS_VIEW="${1:-Sources/ScreenshotApp/Views/SettingsView.swift}"
APP_MODEL="${2:-Sources/ScreenshotApp/Models/AppModel.swift}"
PREFERENCES="${3:-Sources/ScreenshotApp/Support/AppPreferences.swift}"

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
require_text "$PREFERENCES" 'static let historyFraction = "historyFraction"' "history split does not have a persistent preference key"
require_text "$PREFERENCES" 'static let shelfTransparency = "shelfTransparency"' "shelf transparency does not have a persistent preference key"
require_text "$PREFERENCES" "ShelfSplitLayout.defaultHistoryFraction" "history split has no stable default"
require_text "$PREFERENCES" "Self.defaultShelfTransparency" "shelf transparency has no stable default"
require_text "$SETTINGS_VIEW" 'Section("Внешний вид")' "shelf appearance settings are missing"
require_text "$SETTINGS_VIEW" 'Slider(value: $preferences.shelfTransparency, in: 0...1)' "shelf transparency cannot be adjusted continuously"
require_text "$SETTINGS_VIEW" 'Int((preferences.shelfTransparency * 100).rounded())' "shelf transparency percentage is not visible"

echo "SettingsInteractionChecks: OK"
