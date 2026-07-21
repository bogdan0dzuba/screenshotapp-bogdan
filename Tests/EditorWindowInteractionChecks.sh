#!/usr/bin/env bash
set -euo pipefail

CONTROLLER="${1:-Sources/ScreenshotApp/Windowing/EditorWindowController.swift}"
EDITOR_VIEW="${2:-Sources/ScreenshotApp/Views/EditorView.swift}"
EDITOR_CANVAS="${3:-Sources/ScreenshotApp/Views/EditorCanvasView.swift}"
PREFERENCES="${4:-Sources/ScreenshotApp/Support/AppPreferences.swift}"
SETTINGS_VIEW="${5:-Sources/ScreenshotApp/Views/SettingsView.swift}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if ! /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "EditorWindowInteractionChecks: $failure" >&2
    exit 1
  fi
}

require_text "$CONTROLLER" "EditorWindowLayout.contentSize" "editor still ignores screenshot dimensions"
require_text "$CONTROLLER" "contentMinSize" "editor has no compact usable minimum"
require_text "$CONTROLLER" "NSEvent.addLocalMonitorForEvents(matching: .keyDown)" "editor does not receive copy shortcuts"
require_text "$CONTROLLER" "ShelfKeyboardShortcut.isCopy" "editor copy shortcut does not accept both Command-C and Control-C"
require_text "$CONTROLLER" "copySession(" "editor copy paths do not share one completion handler"
require_text "$CONTROLLER" "preferences.closeEditorAfterCopy" "editor ignores the close-after-copy preference"
require_text "$CONTROLLER" "performClose(nil)" "successful copy does not close the editor"
require_text "$EDITOR_VIEW" "ScrollView(.horizontal" "compact editor clips toolbar actions"
require_text "$EDITOR_VIEW" '.keyboardShortcut("c", modifiers: .command)' "editor copy button does not expose standard Command-C"
require_text "$EDITOR_VIEW" "copyAction" "editor copy button bypasses copy completion handling"
require_text "$EDITOR_VIEW" ".frame(width: 36, height: 32)" "editor tool targets are too small"
require_text "$EDITOR_VIEW" ".contentShape(Rectangle())" "editor tool buttons only hit-test their icons"
require_text "$EDITOR_CANVAS" "MagnifyGesture" "editor canvas has no native trackpad pinch gesture"
require_text "$EDITOR_CANVAS" "EditorZoomPolicy.scale" "trackpad magnification bypasses the tested zoom limits"
require_text "$EDITOR_CANVAS" "EditorZoomPolicy.contentSize" "zoom does not resize the scrollable canvas"
require_text "$EDITOR_CANVAS" "draftAnnotation" "editor does not keep a transient annotation while dragging"
require_text "$EDITOR_CANVAS" "AnnotationDraftOverlay" "editor does not draw the selected tool before mouse-up"
require_text "$EDITOR_CANVAS" "session.makeDraft" "live preview does not use the same annotation builder as the final layer"
require_text "$EDITOR_CANVAS" "draftAnnotation = nil" "transient annotation is not cleared after committing"
require_text "$PREFERENCES" "closeEditorAfterCopy" "close-after-copy preference is not persisted"
require_text "$SETTINGS_VIEW" 'Toggle("Закрывать редактор после копирования"' "settings do not expose close-after-copy mode"

echo "EditorWindowInteractionChecks: OK"
