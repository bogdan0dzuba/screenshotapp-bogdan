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
require_text "$SETTINGS_VIEW" 'Picker("Клавиша"' "letter selector has no visible label"
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
require_text "$APP_MODEL" "preferences.setHotKey(activeHotKey)" \
  "failed shortcut preferences are persisted instead of matching the active registration"
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

require_text "$APP_MODEL" '@Published private(set) var activeHotKey: HotKey?' \
  "the actually registered hotkey is not observable UI state"
require_text "$HOT_KEY_SERVICE" 'var registeredHotKey: HotKey?' \
  "the Carbon service does not expose the actually registered shortcut"
require_text "$APP_MODEL" 'activeHotKey = hotKeyService.registeredHotKey' \
  "the model guesses the active shortcut instead of reading the Carbon registration"
require_text "$APP_MODEL" 'ActiveHotKeyFormatter.symbolic(activeHotKey)' \
  "the shelf shortcut is still derived from saved preferences"
require_text "$APP_MODEL" 'ActiveHotKeyFormatter.readable(activeHotKey)' \
  "settings still describe saved preferences instead of the active shortcut"
require_text "$SETTINGS_VIEW" 'LabeledContent("Активная комбинация")' \
  "settings do not distinguish the active shortcut from the editable draft"
require_text "$SETTINGS_VIEW" 'Text(model.hotKeyReadableDescription)' \
  "the active shortcut label does not use the model source of truth"
require_text "$SETTINGS_VIEW" 'LabeledContent("Новая комбинация")' \
  "the editable shortcut preview is mislabeled as active"
require_text "$SETTINGS_VIEW" '.onChange(of: model.activeHotKey)' \
  "an already-open settings window does not follow active shortcut changes"
require_text "$SETTINGS_VIEW" 'if !model.registerHotKey(hotKeyDraft)' \
  "a conflicting draft remains displayed after registration fails"
require_text "$PREFERENCES" 'HotKey.defaultCapture' \
  "preference defaults can drift away from the real standard hotkey"
require_text "$PREFERENCES" 'let storedHotKeyLetter = defaults.string(forKey: Key.hotKeyLetter)?.uppercased()' \
  "legacy shortcut letters are not normalized before Carbon registration"
require_text "$PREFERENCES" 'Self.keyCodes[storedHotKeyLetter] != nil' \
  "an invalid saved letter can register the A key while displaying another symbol"
require_text "$APP_MODEL" 'HotKeyStartupPolicy.candidates(preferred:' \
  "a conflicting saved shortcut does not fall back to the standard hotkey at startup"

echo "SettingsInteractionChecks: OK"
