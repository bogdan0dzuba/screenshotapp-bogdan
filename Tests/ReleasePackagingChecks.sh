#!/usr/bin/env bash
set -euo pipefail

RELEASE_SCRIPT="${1:-script/build_release.sh}"
ARCHIVE="${2:-}"
EXPECTED_VERSION="${SCREENSHOT_APP_VERSION:-0.5.11}"

require_script() {
  local pattern="$1"
  local failure="$2"
  if [[ ! -f "$RELEASE_SCRIPT" ]] || ! /usr/bin/grep -Fq -- "$pattern" "$RELEASE_SCRIPT"; then
    echo "ReleasePackagingChecks: $failure" >&2
    exit 1
  fi
}

require_script "arm64-apple-macosx14.0" "release does not build Apple Silicon"
require_script "x86_64-apple-macosx14.0" "release does not build Intel"
require_script "/usr/bin/lipo -create" "release does not combine both architectures"
require_script "/usr/bin/lipo -archs" "release does not verify the universal binary"
require_script "/usr/bin/codesign --verify" "release does not verify the app signature"
require_script "/usr/bin/ditto -c -k" "release is not packaged as a macOS ZIP"
require_script "/usr/bin/shasum -a 256" "release does not publish a checksum"

if [[ -n "$ARCHIVE" ]]; then
  if [[ ! -f "$ARCHIVE" ]]; then
    echo "ReleasePackagingChecks: archive not found: $ARCHIVE" >&2
    exit 1
  fi

  VERIFY_DIR="$(mktemp -d /private/tmp/ScreenshotApp-release-check.XXXXXX)"
  trap '/bin/rm -rf -- "$VERIFY_DIR"' EXIT
  /usr/bin/ditto -x -k "$ARCHIVE" "$VERIFY_DIR"

  APP_PATH="$VERIFY_DIR/Богдан Скриншот.app"
  BINARY="$APP_PATH/Contents/MacOS/ScreenshotApp"
  [[ -x "$BINARY" ]] || {
    echo "ReleasePackagingChecks: app executable is missing" >&2
    exit 1
  }

  ARCHS="$(/usr/bin/lipo -archs "$BINARY")"
  [[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || {
    echo "ReleasePackagingChecks: expected arm64 and x86_64, got: $ARCHS" >&2
    exit 1
  }
  /usr/bin/codesign --verify --deep --strict "$APP_PATH"
  [[ "$(/usr/bin/plutil -extract CFBundleDisplayName raw "$APP_PATH/Contents/Info.plist")" == "Богдан Скриншот" ]] || {
    echo "ReleasePackagingChecks: public app name is incorrect" >&2
    exit 1
  }
  [[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")" == "$EXPECTED_VERSION" ]] || {
    echo "ReleasePackagingChecks: public app version is incorrect" >&2
    exit 1
  }
  [[ -s "$APP_PATH/Contents/Resources/AppIcon.icns" ]] || {
    echo "ReleasePackagingChecks: app icon is missing from the bundle" >&2
    exit 1
  }
fi

echo "ReleasePackagingChecks: OK"
