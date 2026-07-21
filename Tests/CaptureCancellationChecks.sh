#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-Sources/ScreenshotApp/Windowing/RegionSelectionController.swift}"
SCROLL="${2:-Sources/ScreenshotApp/Windowing/ScrollCaptureController.swift}"
SCROLL_VIEW="${3:-Sources/ScreenshotApp/Views/ScrollCaptureControlsView.swift}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if [[ ! -f "$file" ]] || ! /usr/bin/grep -Fq -- "$pattern" "$file"; then
    echo "CaptureCancellationChecks: $failure" >&2
    exit 1
  fi
}

require_text "$REGION" 'KeyableSelectionPanel(' \
  "selection overlay uses a borderless panel that cannot receive Escape"
require_text "$REGION" 'override var canBecomeKey: Bool { true }' \
  "selection overlay cannot become the key window"
require_text "$REGION" 'override func cancelOperation(_ sender: Any?)' \
  "responder-chain Escape does not cancel region selection"
require_text "$REGION" 'panel.onCancel = ' \
  "selection panel has no Escape fallback when its content responder changes"
require_text "$REGION" 'panel.makeFirstResponder(overlay)' \
  "selection overlay is not the keyboard responder"
require_text "$SCROLL" 'KeyableScrollCapturePanel(' \
  "scroll capture controls cannot receive keyboard cancellation"
require_text "$SCROLL" 'panel.makeKeyAndOrderFront(nil)' \
  "scroll capture controls are never made key"
require_text "$SCROLL" 'panel.onCancel = ' \
  "scroll capture panel has no responder-chain Escape fallback"
require_text "$SCROLL_VIEW" '.onExitCommand { controller.cancel() }' \
  "Escape does not cancel an active scrolling capture"

echo "CaptureCancellationChecks: OK"
