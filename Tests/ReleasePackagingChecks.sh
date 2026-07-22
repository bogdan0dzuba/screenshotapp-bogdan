#!/usr/bin/env bash
set -euo pipefail

RELEASE_SCRIPT="${1:-script/build_release.sh}"
ARCHIVE="${2:-}"
EXPECTED_VERSION="${SCREENSHOT_APP_VERSION:-0.5.17}"

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
require_script "/usr/bin/hdiutil create" "release has no normal macOS disk image installer"
require_script 'ln -s /Applications' "installer image has no Applications shortcut"
require_script "/usr/bin/shasum -a 256" "release does not publish a checksum"
require_script 'ensure_local_signing_identity.sh' "release does not create or reuse a stable signing identity"
require_script 'SCREENSHOT_APP_SIGNING_IDENTITY_MODE:---require-release' \
  "release can silently replace its stable signing identity"
require_script '--ci-adhoc' \
  "CI has no explicitly isolated ad-hoc signing mode"
require_script '"$SIGNING_IDENTITY_MODE"' \
  "release does not pass its signing mode to identity validation"
require_script 'DESIGNATED_REQUIREMENT=' "release has no stable designated requirement"
require_script '--requirements "$DESIGNATED_REQUIREMENT"' "release does not embed its stable designated requirement"
require_script 'if [[ "$SIGNING_IDENTITY_MODE" == "--ci-adhoc" ]]' \
  "ad-hoc signing is not restricted to CI"

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
  if [[ "${SCREENSHOT_APP_ALLOW_ADHOC_SIGNING:-0}" == 1 ]]; then
    /usr/bin/codesign -dvvv "$APP_PATH" 2>&1 | /usr/bin/grep -Fq "Signature=adhoc" || {
      echo "ReleasePackagingChecks: CI archive is not ad-hoc signed" >&2
      exit 1
    }
  else
    ROOT_DIR="$(cd "$(dirname "$RELEASE_SCRIPT")/.." && pwd)"
    bash "$ROOT_DIR/Tests/SigningChecks.sh" "$APP_PATH"
  fi
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
