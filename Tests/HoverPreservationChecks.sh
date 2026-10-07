#!/usr/bin/env bash
set -euo pipefail

CONTROLLER="${1:-Sources/ScreenshotApp/Windowing/RegionSelectionController.swift}"
MODEL="${2:-Sources/ScreenshotApp/Models/AppModel.swift}"
CAPTURE_SERVICE="${3:-Sources/ScreenshotApp/Services/CaptureService.swift}"
HOT_KEY="${4:-Sources/ScreenshotApp/Services/GlobalHotKeyService.swift}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if ! /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "HoverPreservationChecks: $failure" >&2
    exit 1
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if /usr/bin/grep -Fq -- "$pattern" "$file"; then
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

require_text "$MODEL" "case .area: captureArea()" "ordinary area capture bypasses the native area selector"
require_text "$MODEL" "let selection = try await regionSelectionController.selectRegion(using: captureService)" \
  "ordinary area capture does not use the native live selector"
require_text "$MODEL" "selectFrozenRegion(using: captureService)" \
  "scrolling capture loses its frozen hover-preserving first frame"
require_text "$MODEL" "try captureService.write(selection.image, to: request.temporaryURL)" \
  "ordinary area capture recaptures the selected pixels through a legacy API"
require_text "$CAPTURE_SERVICE" "CaptureProcessOutcome.resolve" "native selector cancellation is not handled without a false error"
require_text "$CONTROLLER" "captureFrozenScreen" "scrolling region selection does not freeze the first frame before activating its overlay"
require_order \
  "$CONTROLLER" \
  "captureFrozenScreen" \
  "makeKeyAndOrderFront" \
  "selection overlay can still dismiss hover content before the screen is frozen"
reject_text "$HOT_KEY" 'NSApp.activate()' \
  "global hotkey activates ScreenshotApp before the frozen frame is captured"
require_text "$CONTROLLER" "backdropImage:" "selection overlay does not display the frozen screen"
require_text "$CONTROLLER" "cropFrozenScreen" "selected pixels are recaptured after hover content has disappeared"
require_text "$MODEL" "firstFrame: selection.image" "scrolling capture ignores the hover-preserving first frame"

python3 - "$CONTROLLER" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
live = text[text.index('func selectRegion(using '):text.index('func selectFrozenRegion(using ')]
assert 'captureFrozenScreen' not in live, 'live hotkey must not prepare a full-screen image'
assert live.index('selectLiveRegion(') < live.index('captureSelectedRegion('), 'pixels must be captured after live selection'
assert 'withAlphaComponent(0.42)' not in text, 'full-screen dimming must remain disabled'
PY

echo "HoverPreservationChecks: OK"
