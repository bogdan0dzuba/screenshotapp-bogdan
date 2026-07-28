#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/script/next_release_build_number.sh"

if [[ ! -x "$VALIDATOR" ]]; then
  echo "ReleaseBuildNumberChecks: executable validator is missing: $VALIDATOR" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d /private/tmp/ScreenshotAppBuildNumberChecks.XXXXXX)"
APPCAST_FILE="$TEMP_DIR/appcast.xml"
cleanup() {
  /bin/rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

/bin/cat >"$APPCAST_FILE" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <title>Public release</title>
      <sparkle:version>31</sparkle:version>
      <enclosure />
    </item>
    <item>
      <title>Ignored later item</title>
      <sparkle:version>999</sparkle:version>
      <enclosure />
    </item>
  </channel>
</rss>
XML

accepted_output="$("$VALIDATOR" "32" "$APPCAST_FILE")" || {
  echo "ReleaseBuildNumberChecks: candidate 32 must be accepted after public build 31" >&2
  exit 1
}
if [[ "$accepted_output" != "32" ]]; then
  echo "ReleaseBuildNumberChecks: accepted candidate must be printed exactly" >&2
  exit 1
fi

expect_rejected() {
  local candidate="$1"
  local label="$2"
  if "$VALIDATOR" "$candidate" "$APPCAST_FILE" >/dev/null 2>&1; then
    echo "ReleaseBuildNumberChecks: $label must be rejected" >&2
    exit 1
  fi
}

expect_rejected "31" "candidate equal to public build"
expect_rejected "30" "candidate below public build"
expect_rejected "" "empty candidate"
expect_rejected "thirty-two" "nonnumeric candidate"

echo "ReleaseBuildNumberChecks: OK"
