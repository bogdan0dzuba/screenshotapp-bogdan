#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
swift build --disable-sandbox --product CoreChecks >/dev/null
BIN_DIR="$(swift build --disable-sandbox --show-bin-path)"
TEST_DIR="$(mktemp -d /private/tmp/ScreenshotApp-hotkey-check.XXXXXX)"
trap '/bin/rm -rf -- "$TEST_DIR"' EXIT
if [[ -d "$BIN_DIR/Modules" ]]; then
  CORE_LINK_ARGS=(-I "$BIN_DIR/Modules" "$BIN_DIR"/ScreenshotCore.build/*.o)
else
  CORE_LINK_ARGS=(-I "$BIN_DIR" "$BIN_DIR/ScreenshotCore.o")
fi
swiftc -swift-version 5 -parse-as-library "${CORE_LINK_ARGS[@]}" \
  Sources/ScreenshotApp/Services/GlobalHotKeyService.swift \
  Sources/ScreenshotApp/Services/CaptureTelemetry.swift \
  Tests/HotKeyRegistration/main.swift -o "$TEST_DIR/HotKeyChecks"
"$TEST_DIR/HotKeyChecks"
