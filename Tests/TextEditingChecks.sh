#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /private/tmp/ScreenshotApp-text-editing.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$WORK/cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$WORK/cache}"
cd "$ROOT"
swift build --disable-sandbox --build-system native --product ScreenshotApp
BIN="$(swift build --disable-sandbox --build-system native --show-bin-path)"
APP_OBJECTS=()
for object in "$BIN"/ScreenshotApp.build/*.o; do
  [[ "$(basename "$object")" == "ScreenshotApplication.swift.o" ]] || APP_OBJECTS+=("$object")
done
swiftc -swift-version 5 -parse-as-library -I "$BIN/Modules" \
  "$BIN"/ScreenshotCore.build/*.o "${APP_OBJECTS[@]}" \
  -F "$BIN" -framework Sparkle -Xlinker -rpath -Xlinker "$BIN" \
  Tests/TextEditing/main.swift -o "$WORK/TextEditingChecks"
"$WORK/TextEditingChecks"
