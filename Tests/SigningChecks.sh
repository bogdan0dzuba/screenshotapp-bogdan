#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-$HOME/Applications/Богдан Скриншот.app}"
EXPECTED_IDENTITY="${SCREENSHOT_APP_EXPECTED_SIGNING_IDENTITY:-ScreenshotApp Bogdan Local Signing}"
EXPECTED_CERTIFICATE_SHA1="${SCREENSHOT_APP_EXPECTED_SIGNING_CERTIFICATE_SHA1:-12894FED984452E3FC2AFFDA5758A65BAC1DD2D2}"
EXPECTED_BUNDLE_ID="local.codex.ScreenshotApp"

if [[ ! -d "$APP_PATH" ]]; then
  echo "SigningChecks: app not found: $APP_PATH" >&2
  exit 1
fi

SIGNING_DETAILS="$(/usr/bin/codesign -dvvv "$APP_PATH" 2>&1)"
DESIGNATED_REQUIREMENT="$(/usr/bin/codesign -dr - "$APP_PATH" 2>&1)"

if grep -Fq "Signature=adhoc" <<<"$SIGNING_DETAILS"; then
  echo "SigningChecks: ad-hoc signature changes identity after every build" >&2
  exit 1
fi

grep -Fq "Authority=$EXPECTED_IDENTITY" <<<"$SIGNING_DETAILS" || {
  echo "SigningChecks: expected release signing identity is missing" >&2
  exit 1
}

grep -Fq "identifier \"$EXPECTED_BUNDLE_ID\"" <<<"$DESIGNATED_REQUIREMENT" || {
  echo "SigningChecks: stable bundle identifier is missing from designated requirement" >&2
  exit 1
}

grep -Fiq "certificate leaf = H\"$EXPECTED_CERTIFICATE_SHA1\"" <<<"$DESIGNATED_REQUIREMENT" || {
  echo "SigningChecks: designated requirement does not pin the expected certificate" >&2
  exit 1
}

if grep -Fq "cdhash" <<<"$DESIGNATED_REQUIREMENT"; then
  echo "SigningChecks: designated requirement is tied to one build hash" >&2
  exit 1
fi

echo "SigningChecks: OK"
