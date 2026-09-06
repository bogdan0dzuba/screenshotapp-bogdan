#!/usr/bin/env bash
set -euo pipefail

CONTROLLER="${1:-Sources/ScreenshotApp/Windowing/EditorWindowController.swift}"
EDITOR_VIEW="${2:-Sources/ScreenshotApp/Views/EditorView.swift}"
EDITOR_CANVAS="${3:-Sources/ScreenshotApp/Views/EditorCanvasView.swift}"
PREFERENCES="${4:-Sources/ScreenshotApp/Support/AppPreferences.swift}"
SETTINGS_VIEW="${5:-Sources/ScreenshotApp/Views/SettingsView.swift}"
EDITOR_SESSION="Sources/ScreenshotApp/Models/EditorSession.swift"

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
require_text "$CONTROLLER" "window.minSize" "editor minimum width is not enforced by the window frame"
require_text "$CONTROLLER" "NSEvent.addLocalMonitorForEvents(matching: .keyDown)" "editor does not receive copy shortcuts"
require_text "$CONTROLLER" "ShelfKeyboardShortcut.isCopy" "editor copy shortcut does not accept both Command-C and Control-C"
require_text "$CONTROLLER" "copySession(" "editor copy paths do not share one completion handler"
require_text "$CONTROLLER" "preferences.closeEditorAfterCopy" "editor ignores the close-after-copy preference"
require_text "$CONTROLLER" "performClose(nil)" "successful copy does not close the editor"
require_text "$EDITOR_VIEW" "ScrollView(.horizontal" "compact editor clips toolbar actions"
require_text "$EDITOR_VIEW" '.keyboardShortcut("z", modifiers: .command)' "editor undo button does not expose standard Command-Z"
require_text "$EDITOR_VIEW" '.keyboardShortcut("c", modifiers: .command)' "editor copy button does not expose standard Command-C"
require_text "$EDITOR_VIEW" "copyAction" "editor copy button bypasses copy completion handling"
require_text "$EDITOR_VIEW" ".frame(width: 34, height: 30)" "editor tool targets are too small"
require_text "$EDITOR_VIEW" ".contentShape(Rectangle())" "editor tool buttons only hit-test their icons"
require_text "$EDITOR_VIEW" "ForEach(preferences.editorToolOrder)" "editor palette does not use the saved tool order"
require_text "$EDITOR_VIEW" ".onDrag" "editor tools cannot be dragged"
require_text "$EDITOR_VIEW" ".onDrop" "editor tools cannot be reordered by dropping"
require_text "$EDITOR_VIEW" "ToolReorderDropDelegate" "editor tool reordering has no drop delegate"
require_text "$EDITOR_VIEW" "UTType.text" "editor tool drops do not accept text identifiers"
require_text "$EDITOR_VIEW" "line.3.horizontal" "editor tools have no visible reorder handle"
require_text "$EDITOR_VIEW" ".onHover" "editor reorder handle does not react to hover"
require_text "$EDITOR_VIEW" ".allowsHitTesting(isHovered)" "editor reorder handle is not limited to hover"
require_text "$EDITOR_VIEW" "GeometryReader" "editor toolbar cannot size itself to the window"
require_text "$EDITOR_VIEW" "editorActions" "editor actions are not kept beside the tools"
require_text "$EDITOR_VIEW" ".fixedSize(horizontal: true, vertical: false)" "editor toolbar actions can collapse or clip"
require_text "$EDITOR_VIEW" 'Image(systemName: "doc.on.doc")' "editor copy action has no compact icon"
require_text "$EDITOR_VIEW" 'Image(systemName: "arrow.down.doc")' "editor save-as action has no compact icon"
require_text "$EDITOR_VIEW" 'Image(systemName: "square.and.arrow.down")' "editor save action has no compact icon"

if /usr/bin/grep -Fq "Text(session.tool.title)" "$EDITOR_VIEW"; then
  echo "EditorWindowInteractionChecks: editor toolbar still shows the active tool title" >&2
  exit 1
fi

require_text "$EDITOR_SESSION" "tool: EditorTool = .rectangle" "editor does not select the square tool initially"
require_text "$PREFERENCES" "editorToolOrder" "editor tool order is not persisted"
require_text "$PREFERENCES" "EditorToolOrderPolicy.normalize" "saved editor tools are not normalized"
require_text "$PREFERENCES" "moveEditorTool" "editor preferences cannot persist a reordered palette"
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
