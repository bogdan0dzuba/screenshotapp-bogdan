#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-Sources/ScreenshotApp/Models/AppModel.swift}"
TRANSFER="${2:-Sources/ScreenshotCore/Transfer/ScreenshotTransfer.swift}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if ! /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "KeyActionLatencyChecks: $failure" >&2
    exit 1
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "KeyActionLatencyChecks: $failure" >&2
    exit 1
  fi
}

require_text "$MODEL" 'try activateHotKey(candidateHotKey)' \
  "hotkey registration path is missing"
reject_text "$MODEL" 'DispatchQueue.main.async { self?.handleAreaHotKey() }' \
  "hotkey action still waits through a redundant second main-queue hop"
require_text "$MODEL" 'hotKeyService.register(candidateHotKey) { [weak self] in self?.handleAreaHotKey() }' \
  "hotkey action does not enter the main-actor model directly"
require_text "$TRANSFER" 'let pngData = try Data(contentsOf: url)' \
  "copy still re-encodes an already encoded PNG"
reject_text "$TRANSFER" 'bitmap.representation(using: .png' \
  "copy still converts PNG through TIFF and back to PNG"
require_text "$MODEL" 'try Data(contentsOf: item.imageURL).write(to: destination, options: .atomic)' \
  "PNG Save As still decodes and re-encodes unchanged pixels"

echo "KeyActionLatencyChecks: OK"
