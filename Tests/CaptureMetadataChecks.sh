#!/usr/bin/env bash
set -euo pipefail

PROVIDER="${1:-Sources/ScreenshotApp/Services/CaptureSourceProvider.swift}"
MODEL="${2:-Sources/ScreenshotApp/Models/AppModel.swift}"
HISTORY="${3:-Sources/ScreenshotApp/Services/HistoryStore.swift}"

require_file() {
  local file="$1"
  local failure="$2"
  if [[ ! -f "$file" ]]; then
    echo "CaptureMetadataChecks: $failure" >&2
    exit 1
  fi
}

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if ! /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "CaptureMetadataChecks: $failure" >&2
    exit 1
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "CaptureMetadataChecks: $failure" >&2
    exit 1
  fi
}

require_file "$PROVIDER" "capture source provider is missing"
require_text "$PROVIDER" "NSWorkspace.shared.frontmostApplication" "provider does not read the active application"
require_text "$PROVIDER" "CGWindowListCopyWindowInfo" "provider does not read the available window title"
reject_text "$PROVIDER" "NSAppleScript" "provider would request Automation access"
reject_text "$PROVIDER" "AXUIElement" "provider would request Accessibility access"

require_text "$MODEL" "let source = CaptureSourceProvider.current()" "ordinary capture does not snapshot its source"
require_text "$MODEL" "history.importCapture(at: temporaryURL, source: source)" "ordinary capture drops its source metadata"
require_text "$MODEL" "pendingCaptureSource" "scroll capture has no pending source metadata"
require_text "$MODEL" "history.importImage(image, source: pendingCaptureSource)" "scroll capture drops its source metadata"

require_text "$HISTORY" "func importCapture(at sourceURL: URL, source: CaptureSource? = nil)" "history import does not accept source metadata"
require_text "$HISTORY" "captureSource: source" "history project does not persist source metadata"
require_text "$HISTORY" "captureSource: document?.captureSource" "history reload does not restore source metadata"

echo "CaptureMetadataChecks: OK"
