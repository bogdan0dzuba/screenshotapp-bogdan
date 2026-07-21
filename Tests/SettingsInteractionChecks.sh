#!/usr/bin/env bash
set -euo pipefail

SETTINGS_VIEW="${1:-Sources/ScreenshotApp/Views/SettingsView.swift}"
APP_MODEL="${2:-Sources/ScreenshotApp/Models/AppModel.swift}"
PREFERENCES="${3:-Sources/ScreenshotApp/Support/AppPreferences.swift}"
HOT_KEY_SERVICE="${4:-Sources/ScreenshotApp/Services/GlobalHotKeyService.swift}"

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
require_text "$SETTINGS_VIEW" 'Picker("Клавиша"' "letter selector has no visible label"
require_text "$APP_MODEL" "HotKeyDisplayFormatter.symbolic" "compact shortcut formatting remains hand-written"
require_text "$APP_MODEL" "HotKeyDisplayFormatter.readable" "readable shortcut formatting is missing"
require_text "$SETTINGS_VIEW" '@State private var draftHotKeyLetter' \
  "hotkey controls still persist an unverified shortcut before Apply is pressed"
require_text "$SETTINGS_VIEW" 'model.registerHotKey(hotKeyDraft)' \
  "Apply does not validate the complete draft shortcut transactionally"
require_text "$SETTINGS_VIEW" 'HotKeyDisplayFormatter.readable(hotKeyDraft)' \
  "settings do not preview the candidate shortcut before registration"
require_text "$HOT_KEY_SERVICE" "HotKeyRegistrationStore<EventHotKeyRef>" \
  "hotkey replacement is not transactional"
require_text "$HOT_KEY_SERVICE" "eventHotKeyExistsErr" \
  "Carbon hotkey conflicts are not distinguished from unknown registration errors"
require_text "$HOT_KEY_SERVICE" "уже занято macOS или другим приложением" \
  "hotkey conflict has no actionable Russian explanation"
require_text "$APP_MODEL" "private var registeredHotKey" \
  "settings cannot restore the previously working shortcut after a conflict"
require_text "$APP_MODEL" "preferences.setHotKey(previousHotKey)" \
  "failed shortcut preferences are persisted instead of being rolled back"
require_text "$APP_MODEL" "presentHotKeyRegistrationError" \
  "hotkey conflicts still use the unrelated screenshot-permission alert"
require_text "$PREFERENCES" "func setHotKey(_ hotKey: HotKey)" \
  "preferences cannot restore a previously working shortcut"
require_text "$PREFERENCES" 'static let historyFraction = "historyFraction"' "history split does not have a persistent preference key"
require_text "$PREFERENCES" 'static let shelfTransparency = "shelfTransparency"' "shelf transparency does not have a persistent preference key"
require_text "$PREFERENCES" "ShelfSplitLayout.defaultHistoryFraction" "history split has no stable default"
require_text "$PREFERENCES" 'static let historyFractionRevision = "historyFractionRevision"' "history split default cannot migrate without overwriting a custom size"
require_text "$PREFERENCES" "currentHistoryFractionRevision" "history split migration has no revision marker"
require_text "$PREFERENCES" "Self.defaultShelfTransparency" "shelf transparency has no stable default"
require_text "$SETTINGS_VIEW" 'Section("Внешний вид")' "shelf appearance settings are missing"
require_text "$SETTINGS_VIEW" 'Slider(value: $preferences.shelfTransparency, in: 0...1)' "shelf transparency cannot be adjusted continuously"
require_text "$SETTINGS_VIEW" 'Int((preferences.shelfTransparency * 100).rounded())' "shelf transparency percentage is not visible"
require_text "$PREFERENCES" 'static let automaticallyDeletesOldCaptures = "automaticallyDeletesOldCaptures"' "automatic cleanup has no persistent preference key"
require_text "$PREFERENCES" '@Published var automaticallyDeletesOldCaptures: Bool' "automatic cleanup cannot be changed"
require_text "$PREFERENCES" 'defaults.set(automaticallyDeletesOldCaptures' "automatic cleanup preference is not persisted"
require_text "$SETTINGS_VIEW" '"Автоматически удалять старые снимки"' "history has no automatic cleanup toggle"
require_text "$SETTINGS_VIEW" '.disabled(!preferences.automaticallyDeletesOldCaptures)' "retention limits remain active-looking when cleanup is disabled"
require_text "$APP_MODEL" 'automaticCleanupEnabled: preferences.automaticallyDeletesOldCaptures' "automatic cleanup preference is not propagated to history"

echo "SettingsInteractionChecks: OK"
