#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
swift build --disable-sandbox --product CoreChecks >/dev/null
BIN_DIR="$(swift build --disable-sandbox --show-bin-path)"
TEST_DIR="$(mktemp -d /private/tmp/ScreenshotApp-permission-check.XXXXXX)"
trap '/bin/rm -rf -- "$TEST_DIR"' EXIT
swiftc -swift-version 5 -parse-as-library \
  -I "$BIN_DIR/Modules" \
  "$BIN_DIR"/ScreenshotCore.build/*.o \
  Sources/ScreenshotApp/Services/CaptureService.swift \
  Sources/ScreenshotApp/Services/CaptureTelemetry.swift \
  Sources/ScreenshotApp/Services/SelectedContentFrameCapture.swift \
  Tests/CaptureServicePermission/main.swift \
  -o "$TEST_DIR/PermissionChecks"
"$TEST_DIR/PermissionChecks"
