#!/usr/bin/env bash
set -euo pipefail

BUILD_PRODUCT="ScreenshotApp"
APP_NAME="Богдан Скриншот"
BUNDLE_ID="local.codex.ScreenshotApp"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${SCREENSHOT_APP_VERSION:-0.5.12}"
BUILD_NUMBER="${SCREENSHOT_APP_BUILD_NUMBER:-26}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="/private/tmp/ScreenshotApp-Bogdan-release-stage-$(id -u)"
APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$BUILD_PRODUCT"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Assets/AppIcon.icns"
ARM_BUILD_DIR="/private/tmp/ScreenshotApp-Bogdan-release-arm64-$(id -u)"
INTEL_BUILD_DIR="/private/tmp/ScreenshotApp-Bogdan-release-x86_64-$(id -u)"
BUILD_CACHE_DIR="/private/tmp/ScreenshotApp-Bogdan-release-cache-$(id -u)"
ARCHIVE_NAME="ScreenshotApp-Bogdan-macOS-Universal.zip"
DELIVERABLE_ZIP="$DIST_DIR/$ARCHIVE_NAME"
CHECKSUM_FILE="$DELIVERABLE_ZIP.sha256"

prepare_swift_environment() {
  mkdir -p "$BUILD_CACHE_DIR/clang" "$BUILD_CACHE_DIR/swiftpm"
  export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$BUILD_CACHE_DIR/clang}"
  export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$BUILD_CACHE_DIR/swiftpm}"

  if [[ -n "${SDKROOT:-}" ]]; then
    return
  fi

  local default_sdk
  default_sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
  local probe_dir="$BUILD_CACHE_DIR/sdk-probe-$$"
  local probe_source="$probe_dir/probe.swift"
  local probe_log="$probe_dir/probe.log"
  mkdir -p "$probe_dir/default-cache"
  printf 'import Foundation\n' >"$probe_source"

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

build_architecture() {
  local triple="$1"
  local scratch_path="$2"
  swift build \
    --disable-sandbox \
    --configuration release \
    --triple "$triple" \
    --scratch-path "$scratch_path" \
    --product "$BUILD_PRODUCT"
}

cd "$ROOT_DIR"
prepare_swift_environment
bash "$ROOT_DIR/Tests/CaptureMetadataChecks.sh"
bash "$ROOT_DIR/Tests/CapturePerformanceChecks.sh"
bash "$ROOT_DIR/Tests/HoverPreservationChecks.sh"
bash "$ROOT_DIR/Tests/ShelfPanelInteractionChecks.sh"
bash "$ROOT_DIR/Tests/AppIdentityChecks.sh"

/bin/rm -rf -- "$STAGE_DIR" "$ARM_BUILD_DIR" "$INTEL_BUILD_DIR"
mkdir -p "$DIST_DIR" "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"

build_architecture "arm64-apple-macosx14.0" "$ARM_BUILD_DIR"
build_architecture "x86_64-apple-macosx14.0" "$INTEL_BUILD_DIR"

ARM_BINARY="$ARM_BUILD_DIR/arm64-apple-macosx/release/$BUILD_PRODUCT"
INTEL_BINARY="$INTEL_BUILD_DIR/x86_64-apple-macosx/release/$BUILD_PRODUCT"
/usr/bin/lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$APP_BINARY"
chmod +x "$APP_BINARY"
/bin/cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
/usr/bin/ditto \
  "$ARM_BUILD_DIR/arm64-apple-macosx/release/Sparkle.framework" \
  "$APP_FRAMEWORKS/Sparkle.framework"

ARCHS="$(/usr/bin/lipo -archs "$APP_BINARY")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || {
  echo "Не удалось создать Universal-бинарник: $ARCHS" >&2
  exit 1
}

/usr/bin/plutil -create xml1 "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleExecutable -string "$BUILD_PRODUCT" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleName -string "$APP_NAME" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleDisplayName -string "$APP_NAME" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleIconFile -string AppIcon "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$INFO_PLIST"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "$MIN_SYSTEM_VERSION" "$INFO_PLIST"
/usr/bin/plutil -insert LSUIElement -bool YES "$INFO_PLIST"
/usr/bin/plutil -insert NSHighResolutionCapable -bool YES "$INFO_PLIST"
/usr/bin/plutil -insert NSPrincipalClass -string NSApplication "$INFO_PLIST"
/usr/bin/plutil -insert NSScreenCaptureUsageDescription -string \
  "Приложению нужен доступ к экрану, чтобы создавать выбранные вами снимки." \
  "$INFO_PLIST"
/usr/bin/plutil -insert SUFeedURL -string \
  "https://github.com/bogdan0dzuba/screenshotapp-bogdan/releases/latest/download/appcast.xml" \
  "$INFO_PLIST"
/usr/bin/plutil -insert SUPublicEDKey -string \
  "fhGTeCAerHeifyqZb9B3uETRm5mFSfIcTE8pW/HyjP0=" \
  "$INFO_PLIST"
/usr/bin/plutil -insert SUEnableAutomaticChecks -bool YES "$INFO_PLIST"
/usr/bin/plutil -insert SUScheduledCheckInterval -integer 21600 "$INFO_PLIST"
/usr/bin/plutil -insert SUAllowsAutomaticUpdates -bool YES "$INFO_PLIST"
/usr/bin/plutil -insert SUAutomaticallyUpdate -bool NO "$INFO_PLIST"

/usr/bin/xattr -cr "$APP_BUNDLE"
if [[ -n "${SCREENSHOT_APP_SIGNING_IDENTITY:-}" ]]; then
  /usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$SCREENSHOT_APP_SIGNING_IDENTITY" \
    "$APP_FRAMEWORKS/Sparkle.framework"
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SCREENSHOT_APP_SIGNING_IDENTITY" \
    "$APP_BUNDLE"
else
  echo "Developer ID не задан: используется ad-hoc подпись для открытой тестовой версии."
  /usr/bin/codesign --force --sign - "$APP_BUNDLE"
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

/bin/rm -f -- "$DELIVERABLE_ZIP" "$CHECKSUM_FILE"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$DELIVERABLE_ZIP"
(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 "$ARCHIVE_NAME" >"$ARCHIVE_NAME.sha256"
)

bash "$ROOT_DIR/Tests/ReleasePackagingChecks.sh" "$ROOT_DIR/script/build_release.sh" "$DELIVERABLE_ZIP"

echo "Готово: $DELIVERABLE_ZIP"
echo "Архитектуры: $ARCHS"
echo "SHA-256: $(/usr/bin/awk '{print $1}' "$CHECKSUM_FILE")"
