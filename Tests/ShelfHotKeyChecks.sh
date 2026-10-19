#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /private/tmp/ScreenshotApp-shelf-hotkey.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"
cd "$ROOT"
swift build --disable-sandbox --build-system native --product ScreenshotApp >/dev/null
BIN="$(swift build --disable-sandbox --build-system native --show-bin-path)"
APP_OBJECTS=()
for object in "$BIN"/ScreenshotApp.build/*.o; do
  [[ "$(basename "$object")" == "ScreenshotApplication.swift.o" ]] || APP_OBJECTS+=("$object")
done
swiftc -sdk "$SDKROOT" -swift-version 5 -parse-as-library -I "$BIN/Modules" \
  "$BIN"/ScreenshotCore.build/*.o "${APP_OBJECTS[@]}" \
  -F "$BIN" -framework Sparkle -Xlinker -rpath -Xlinker "$BIN" \
  Tests/ShelfHotKey/main.swift -o "$WORK/ShelfHotKeyChecks"
"$WORK/ShelfHotKeyChecks"
