#!/usr/bin/env bash
set -euo pipefail

CONTROLLER="${1:-Sources/ScreenshotApp/Windowing/RegionSelectionController.swift}"
MODEL="${2:-Sources/ScreenshotApp/Models/AppModel.swift}"
CAPTURE_SERVICE="${3:-Sources/ScreenshotApp/Services/CaptureService.swift}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if ! /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "HoverPreservationChecks: $failure" >&2
    exit 1
  fi
}

require_order() {
  local file="$1"
  local first="$2"
  local second="$3"
  local failure="$4"
  local first_line second_line
  first_line="$(/usr/bin/grep -Fn "$first" "$file" | /usr/bin/head -1 | /usr/bin/cut -d: -f1 || true)"
  second_line="$(/usr/bin/grep -Fn "$second" "$file" | /usr/bin/head -1 | /usr/bin/cut -d: -f1 || true)"
  if [[ -z "$first_line" || -z "$second_line" || "$first_line" -ge "$second_line" ]]; then
    echo "HoverPreservationChecks: $failure" >&2
    exit 1
  fi
}

require_text "$MODEL" "case .area: captureArea()" "ordinary area capture still launches the legacy screencapture process"
require_text "$MODEL" "let selection = try await regionSelectionController.selectRegion(using: captureService)" \
  "ordinary area capture does not use the ScreenCaptureKit-backed frozen selector"
require_text "$MODEL" "try captureService.write(selection.image, to: request.temporaryURL)" \
  "ordinary area capture recaptures the selected pixels through a legacy API"
require_text "$CAPTURE_SERVICE" "CaptureProcessOutcome.resolve" "native selector cancellation is not handled without a false error"
require_text "$CONTROLLER" "captureFrozenScreen" "scrolling region selection does not freeze the first frame before activating its overlay"
require_order \
  "$CONTROLLER" \
  "captureFrozenScreen" \
  "makeKeyAndOrderFront" \
  "selection overlay can still dismiss hover content before the screen is frozen"
require_text "$CONTROLLER" "backdropImage:" "selection overlay does not display the frozen screen"
require_text "$CONTROLLER" "cropFrozenScreen" "selected pixels are recaptured after hover content has disappeared"
require_text "$MODEL" "firstFrame: selection.image" "scrolling capture ignores the hover-preserving first frame"

echo "HoverPreservationChecks: OK"
