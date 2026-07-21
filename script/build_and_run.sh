#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
BUILD_PRODUCT="ScreenshotApp"
APP_NAME="Богдан Скриншот"
PROCESS_NAME="ScreenshotApp"
BUNDLE_ID="local.codex.ScreenshotApp"
MIN_SYSTEM_VERSION="14.0"
SIGNING_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="/private/tmp/ScreenshotApp-Bogdan-stage-$(id -u)"
APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"
DELIVERABLE_ZIP="$DIST_DIR/ScreenshotApp-Bogdan-macOS.zip"
INSTALL_DIR="${SCREENSHOT_APP_INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
LEGACY_INSTALLED_APP="$INSTALL_DIR/ScreenshotApp Bogdan.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$BUILD_PRODUCT"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Assets/AppIcon.icns"
BUILD_CACHE_DIR="/private/tmp/ScreenshotApp-Bogdan-build-cache-$(id -u)"

prepare_swift_environment() {
  mkdir -p "$BUILD_CACHE_DIR/clang" "$BUILD_CACHE_DIR/swiftpm"
  export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$BUILD_CACHE_DIR/clang}"
  export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$BUILD_CACHE_DIR/swiftpm}"

  if [[ -n "${SDKROOT:-}" ]]; then
    return
  fi

  local probe_dir="$BUILD_CACHE_DIR/sdk-probe-$$"
  local probe_source="$probe_dir/probe.swift"
  local probe_log="$probe_dir/probe.log"
  local default_sdk
  mkdir -p "$probe_dir/default-cache"
  printf 'import Foundation\n' >"$probe_source"
  default_sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
  if /usr/bin/swiftc \
    -typecheck \
    -sdk "$default_sdk" \
    -module-cache-path "$probe_dir/default-cache" \
    "$probe_source" \
    >/dev/null 2>"$probe_log"; then
    /bin/rm -rf -- "$probe_dir"
    return
  fi

  if ! /usr/bin/grep -Fq "SDK is not supported by the compiler" "$probe_log"; then
    /bin/cat "$probe_log" >&2
    /bin/rm -rf -- "$probe_dir"
    exit 1
  fi

  local candidate
  for candidate in /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; do
    [[ -d "$candidate" ]] || continue
    mkdir -p "$probe_dir/fallback-cache"
    if /usr/bin/swiftc \
      -typecheck \
      -sdk "$candidate" \
      -module-cache-path "$probe_dir/fallback-cache" \
      "$probe_source" \
      >/dev/null 2>"$probe_log"; then
      export SDKROOT="$candidate"
      echo "Используется совместимый SDK: $candidate"
      /bin/rm -rf -- "$probe_dir"
      return
    fi
  done

  /bin/cat "$probe_log" >&2
  /bin/rm -rf -- "$probe_dir"
  exit 1
}

pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
prepare_swift_environment
swift build --disable-sandbox
bash "$ROOT_DIR/Tests/CaptureMetadataChecks.sh"
bash "$ROOT_DIR/Tests/CapturePerformanceChecks.sh"
bash "$ROOT_DIR/Tests/HoverPreservationChecks.sh"
bash "$ROOT_DIR/Tests/ShelfPanelInteractionChecks.sh"
bash "$ROOT_DIR/Tests/EditorWindowInteractionChecks.sh"
bash "$ROOT_DIR/Tests/SettingsInteractionChecks.sh"
bash "$ROOT_DIR/Tests/AppIdentityChecks.sh"
BUILD_BINARY="$(swift build --disable-sandbox --show-bin-path)/$BUILD_PRODUCT"

rm -rf "$STAGE_DIR"
rm -rf "$DIST_DIR/$APP_NAME.app"
rm -rf "$DIST_DIR/ScreenshotApp.app"
rm -f "$DIST_DIR/ScreenshotApp-macOS.zip"
mkdir -p "$DIST_DIR"
mkdir -p "$INSTALL_DIR"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY"
BUILD_BIN_DIR="$(dirname "$BUILD_BINARY")"
/usr/bin/ditto "$BUILD_BIN_DIR/Sparkle.framework" "$APP_FRAMEWORKS/Sparkle.framework"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$BUILD_PRODUCT</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>0.5.11</string>
  <key>CFBundleVersion</key>
  <string>25</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Приложению нужен доступ к экрану, чтобы создавать выбранные вами снимки.</string>
  <key>SUFeedURL</key>
  <string>https://github.com/bogdan0dzuba/screenshotapp-bogdan/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>fhGTeCAerHeifyqZb9B3uETRm5mFSfIcTE8pW/HyjP0=</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>21600</integer>
  <key>SUAllowsAutomaticUpdates</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <false/>
</dict>
</plist>
PLIST

/usr/bin/xattr -cr "$APP_BUNDLE"
SIGNING_CERT_SHA1="$("$ROOT_DIR/script/ensure_local_signing_identity.sh")"
DESIGNATED_REQUIREMENT="=designated => identifier \"$BUNDLE_ID\" and certificate leaf = H\"$SIGNING_CERT_SHA1\""
/usr/bin/codesign \
  --force \
  --keychain "$SIGNING_KEYCHAIN" \
  --sign "$SIGNING_CERT_SHA1" \
  --requirements "$DESIGNATED_REQUIREMENT" \
  "$APP_BUNDLE" \
  >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
bash "$ROOT_DIR/Tests/SigningChecks.sh" "$APP_BUNDLE"

rm -rf "$INSTALLED_APP"
/usr/bin/ditto --norsrc "$APP_BUNDLE" "$INSTALLED_APP"
/usr/bin/xattr -cr "$INSTALLED_APP"
/usr/bin/codesign --verify --deep --strict "$INSTALLED_APP"
if [[ "$LEGACY_INSTALLED_APP" != "$INSTALLED_APP" && -d "$LEGACY_INSTALLED_APP" ]]; then
  /bin/rm -rf -- "$LEGACY_INSTALLED_APP"
fi
rm -f "$DELIVERABLE_ZIP"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$DELIVERABLE_ZIP"

ARCHIVE_VERIFY_DIR="$STAGE_DIR/archive-verify"
mkdir -p "$ARCHIVE_VERIFY_DIR"
/usr/bin/ditto -x -k "$DELIVERABLE_ZIP" "$ARCHIVE_VERIFY_DIR"
/usr/bin/codesign --verify --deep --strict "$ARCHIVE_VERIFY_DIR/$APP_NAME.app"
bash "$ROOT_DIR/Tests/SigningChecks.sh" "$ARCHIVE_VERIFY_DIR/$APP_NAME.app"

open_app() {
  /usr/bin/open -n "$INSTALLED_APP"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$PROCESS_NAME" >/dev/null
    /usr/bin/codesign --verify --deep --strict "$INSTALLED_APP"
    bash "$ROOT_DIR/Tests/SigningChecks.sh" "$INSTALLED_APP"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
