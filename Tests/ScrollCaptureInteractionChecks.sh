#!/usr/bin/env bash
set -euo pipefail

CONTROLLER="${1:-Sources/ScreenshotApp/Windowing/ScrollCaptureController.swift}"
CONTROLS="${2:-Sources/ScreenshotApp/Views/ScrollCaptureControlsView.swift}"
REGION_SELECTION="${3:-Sources/ScreenshotApp/Windowing/RegionSelectionController.swift}"
CAPTURE_SERVICE="${4:-Sources/ScreenshotApp/Services/CaptureService.swift}"
COVERAGE_VIEW="${5:-Sources/ScreenshotCore/Scrolling/ScrollCaptureCoverageView.swift}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if ! /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "ScrollCaptureInteractionChecks: $failure" >&2
    exit 1
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "ScrollCaptureInteractionChecks: $failure" >&2
    exit 1
  fi
}

require_text "$CONTROLLER" "ScrollCaptureFinishPolicy.canFinish" "finish is still coupled to an in-flight frame"
require_text "$CONTROLLER" "ScrollCaptureStartPolicy.canStart" "scroll capture still begins before the selected area is confirmed"
require_text "$CONTROLLER" "func start()" "the selected area has no explicit Start phase"
require_text "$CONTROLLER" "ScrollCaptureFeedbackOverlay" "selected scroll area has no persistent visual guide"
require_text "$CONTROLLER" "ScrollCaptureFeedbackPolicy.state(for: outcome)" "visual feedback is not tied to the settled frame decision"
require_text "$CONTROLLER" "feedbackOverlay.present(state: feedbackState" "accepted and rejected frames have no distinct guide state"
reject_text "$CONTROLLER" "ScrollCaptureGuideView" "the redundant lower guide can still cover the selected scroll area"
reject_text "$CONTROLLER" "guidePanel" "a fallback guide panel can still be placed inside the selected scroll area"
require_text "$CONTROLLER" "panel.hidesOnDeactivate = false" "scroll guides disappear when the user returns to the captured app"
require_text "$CONTROLLER" "ScrollCapturePanelPlacement.frame" "the control HUD is not anchored to the selected area"
require_text "$CONTROLLER" "panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)" "the dimming overlay can cover the Start and Done controls"
require_text "$CONTROLLER" "outsideShadePanels" "screen outside the selected scroll area is not dimmed"
require_text "$CONTROLLER" "ScrollCaptureCoverageView" "captured and pending portions have no persistent visual mask"
require_text "$COVERAGE_VIEW" "externalRects" "accepted scroll progress has no visible external trail"
require_text "$CONTROLLER" "ScrollCapturePreviewCanvas" "the accepted content has no growing preview of the real stitch"
require_text "$CONTROLLER" "previewPanel" "the growing stitch has no rail panel beside the selection"
require_text "$CONTROLLER" "ScrollCapturePreviewPlacement.frame" "the preview rail is not anchored beside the selected area"
require_text "$CONTROLLER" "previewPanel.ignoresMouseEvents = true" "the preview rail can swallow clicks over the scrolled page"
reject_text "$CONTROLLER" "sharingType = .none" "scroll capture guides are hidden from screen recording, so the result cannot be shown or verified"
require_text "$CONTROLLER" "previewPanel.sharingType = .readOnly" "the preview rail has no explicit screen-sharing policy"
require_text "$CONTROLLER" "previewCanvas.undoLast()" "removing a frame does not shrink the accumulated preview"
require_text "$CONTROLLER" "AXIsProcessTrustedWithOptions" "auto scrolling never asks for the Accessibility permission it needs"
require_text "$CONTROLLER" "ScrollAutoAdvancePolicy.step" "auto scrolling picks its step size ad hoc instead of using a shared policy"
require_text "$CONTROLLER" "CGWarpMouseCursorPosition" "auto scrolling posts wheel events without aiming them at the selected area"
cancel_teardown="$(/usr/bin/sed -n '/func cancel()/,/^    }/p' "$CONTROLLER" | /usr/bin/grep -Ec "feedbackOverlay.hide\(\)|hidePreviewPanel\(\)" || true)"
if (( cancel_teardown < 2 )); then
  echo "ScrollCaptureInteractionChecks: cancelling a scroll capture leaves guides or the preview rail on screen" >&2
  exit 1
fi
finish_teardown="$(/usr/bin/sed -n '/func finish()/,/^    }/p' "$CONTROLLER" | /usr/bin/grep -Ec "feedbackOverlay.hide\(\)|hidePreviewPanel\(\)" || true)"
if (( finish_teardown < 2 )); then
  echo "ScrollCaptureInteractionChecks: finishing a scroll capture leaves guides or the preview rail on screen" >&2
  exit 1
fi
autoscroll_stops="$(/usr/bin/grep -Fc "stopAutoScroll(" "$CONTROLLER" || true)"
if (( autoscroll_stops < 6 )); then
  echo "ScrollCaptureInteractionChecks: auto scrolling keeps running after pause, undo, finish or cancel" >&2
  exit 1
fi
require_text "$CONTROLLER" "classificationFrames" "hover-preserving output is still reused as the automatic comparison baseline"
require_text "$CONTROLLER" "Подготавливаю стабильный первый кадр" "Start does not prepare a stable filtered baseline before asking the user to scroll"
require_text "$CONTROLLER" "overlap: overlap" "classifier-approved seams are discarded before final stitching"
require_text "$CONTROLLER" "ScrollCaptureCoveragePolicy.coverage" "progress mask is not tied to the accepted overlap"
require_text "$CONTROLLER" "presentCapturedViewport()" "an accepted live viewport is not marked as fully scanned"
require_text "$COVERAGE_VIEW" "markedRect.fill()" "the scanned part of the live viewport has no persistent color mark"
require_text "$COVERAGE_VIEW" "presentNeedsOverlap()" "an overlap warning can erase the last captured viewport"
reject_text "$CONTROLLER" "presentLive()" "a recovery branch can still erase the captured-area mark"
reject_text "$CONTROLLER" "frozenFrame.draw(" "a frozen screenshot can still create double text over the live viewport"
reject_text "$CONTROLLER" 'drawLabel("СНЯТО' "the accepted-frame label still obscures live content"
reject_text "$CONTROLLER" 'drawLabel("ЕЩЁ НЕ СНЯТО' "the pending-frame label still obscures live content"
require_text "$CONTROLLER" "preparedCapture" "automatic frames are not tied to an overlay-safe capture source"
reject_text "$CONTROLLER" "NSApp.activate(ignoringOtherApps: true)" "the scrolling HUD steals focus from the app being scrolled"
require_text "$CONTROLLER" "settler.observe" "frames are still accepted while the viewport is moving"
require_text "$CONTROLLER" "ScrollFrameNormalizer.normalized" "Retina-sized frames can still fail final stitching"
require_text "$CONTROLLER" "Прокрутите на 1/3 и остановитесь" "scroll pacing is not explained to the user"
release_call_count="$(/usr/bin/grep -Fc "releaseCapturedFrames()" "$CONTROLLER" || true)"
if (( release_call_count < 3 )); then
  echo "ScrollCaptureInteractionChecks: full-size scroll frames remain retained after success or cancellation" >&2
  exit 1
fi
require_text "$CONTROLS" "controller.canFinish" "Done remains disabled while a frame is captured"
require_text "$CONTROLS" 'Button("Начать", action: controller.start)' "the control HUD has no explicit Start button"
require_text "$CONTROLS" "controller.toggleAutoScroll" "the control HUD cannot start auto scrolling"
require_text "$CONTROLS" 'Text("Esc - отмена")' "the control HUD does not explain how to cancel from the keyboard"
require_text "$CONTROLS" '.environment(\.appearsActive, true)' "the first HUD presentation still inherits an unreadable inactive control state"
require_text "$CONTROLS" 'Color(nsColor: .windowBackgroundColor)' "the command HUD still depends on a translucent backdrop for legibility"
reject_text "$CONTROLS" "ProgressView" "background polling still replaces the stable status icon with a spinner"
reject_text "$CONTROLS" "isProcessingFrame" "background polling still disables HUD actions per frame"
reject_text "$CONTROLS" "keyboardShortcut(.return" "the default Return button can still pulse during polling"
reject_text "$CONTROLLER" "CAKeyframeAnimation" "feedback still flashes on every polling outcome"
require_text "$CAPTURE_SERVICE" "struct PreparedScrollCapture" "scroll capture has no reusable filtered source"
require_text "$CAPTURE_SERVICE" "excludingApplications: excludedApplications" "ScreenshotApp overlays are not excluded from automatic frames"
require_text "$CAPTURE_SERVICE" "SCScreenshotManager.captureImage(" "automatic frames do not use ScreenCaptureKit"
require_text "$CAPTURE_SERVICE" "contentFilter: prepared.contentFilter" "automatic frames still use an unfiltered screen rectangle"
require_text "$REGION_SELECTION" 'panel.title = "Выбор области снимка"' "selection window has no accessible identity for physical UI testing"

echo "ScrollCaptureInteractionChecks: OK"
