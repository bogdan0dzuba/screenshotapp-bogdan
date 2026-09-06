#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-Sources/ScreenshotApp/Windowing/RegionSelectionController.swift}"
SCROLL="${2:-Sources/ScreenshotApp/Windowing/ScrollCaptureController.swift}"
SCROLL_VIEW="${3:-Sources/ScreenshotApp/Views/ScrollCaptureControlsView.swift}"
MODEL="${4:-Sources/ScreenshotApp/Models/AppModel.swift}"
HOT_KEY="${5:-Sources/ScreenshotApp/Services/GlobalHotKeyService.swift}"
APP_DELEGATE="${6:-Sources/ScreenshotApp/App/AppDelegate.swift}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if [[ ! -f "$file" ]] || ! /usr/bin/grep -Fq -- "$pattern" "$file"; then
    echo "CaptureCancellationChecks: $failure" >&2
    exit 1
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if [[ -f "$file" ]] && /usr/bin/grep -Fq -- "$pattern" "$file"; then
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
require_text "$REGION" 'panel.orderFrontRegardless()' \
  "selection overlay can remain hidden until the app is manually opened"
require_text "$REGION" 'func focusPendingOverlayIfNeeded()' \
  "a pending selection cannot recover keyboard focus after activation"
reject_text "$REGION" 'NSApp.activate(ignoringOtherApps: true)' \
  "selection overlay still relies on the deprecated activation call"
reject_text "$HOT_KEY" 'NSApp.activate()' \
  "global hotkey activates ScreenshotApp before the frozen frame is captured"
require_text "$APP_DELEGATE" 'applicationDidBecomeActive' \
  "selection overlay is not focused after an accepted activation request"
require_text "$REGION" 'func cancelActiveSelection() -> Bool' \
  "a repeated global hotkey cannot cancel an invisible area selector"
require_text "$MODEL" 'recoverAreaCaptureFromHotKey()' \
  "a repeated global hotkey is still silently ignored while an area capture is active"
require_text "$MODEL" 'activeAreaCaptureTask?.cancel()' \
  "the active area capture is not cancelled before retrying the hotkey"
require_text "$MODEL" 'cancelActiveSelection()' \
  "the active selector is not dismissed before retrying the hotkey"
require_text "$MODEL" 'restartAreaCaptureAfterCancellation' \
  "restarting a stuck selector can lose the next requested capture"
require_text "$SCROLL" 'KeyableScrollCapturePanel(' \
  "scroll capture controls cannot receive keyboard cancellation"
require_text "$SCROLL" 'panel.makeKeyAndOrderFront(nil)' \
  "scroll capture controls are never made key"
require_text "$SCROLL" 'panel.onCancel = ' \
  "scroll capture panel has no responder-chain Escape fallback"
require_text "$SCROLL_VIEW" '.onExitCommand { controller.cancel() }' \
  "Escape does not cancel an active scrolling capture"

echo "CaptureCancellationChecks: OK"
