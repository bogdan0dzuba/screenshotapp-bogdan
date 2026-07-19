#!/usr/bin/env bash
set -euo pipefail

require_text() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if [[ ! -f "$file" ]] || ! /usr/bin/grep -Fq -- "$pattern" "$file"; then
    echo "UpdaterIntegrationChecks: $message" >&2
    exit 1
  fi
}

require_text Package.swift 'sparkle-project/Sparkle' "Sparkle package is not configured"
require_text Sources/ScreenshotApp/Services/UpdateService.swift 'SPUStandardUpdaterController' \
  "standard Sparkle updater is not initialized"
require_text Sources/ScreenshotApp/Views/MenuBarView.swift 'updateService.checkForUpdates()' \
  "manual update action is not connected to Sparkle"
require_text Sources/ScreenshotApp/Views/SettingsView.swift 'Автоматически проверять обновления' \
  "automatic update setting is missing"
require_text script/build_release.sh 'SUFeedURL' "release bundle has no appcast URL"
require_text script/build_release.sh 'SUPublicEDKey' "release bundle has no EdDSA public key"
require_text .github/workflows/release.yml 'SPARKLE_PRIVATE_KEY' \
  "release workflow does not use the protected Sparkle key"
require_text .github/workflows/release.yml 'appcast.xml' "release workflow does not publish an appcast"

if /usr/bin/grep -Fq -- 'runs-on: macos-15-intel' .github/workflows/release.yml; then
  echo "UpdaterIntegrationChecks: Intel runner reproducibly kills CoreChecks after linking" >&2
  exit 1
fi
require_text .github/workflows/release.yml 'swift build --disable-sandbox --product CoreChecks' \
  "CI does not build CoreChecks in an isolated SwiftPM process"
require_text .github/workflows/release.yml '.build/debug/CoreChecks' \
  "CI does not execute the already-built CoreChecks binary"

echo "UpdaterIntegrationChecks: OK"
