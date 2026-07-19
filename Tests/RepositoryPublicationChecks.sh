#!/usr/bin/env bash
set -euo pipefail

README="${1:-README.md}"
WORKFLOW="${2:-.github/workflows/release.yml}"
GITIGNORE="${3:-.gitignore}"
MENU_BAR="${4:-Sources/ScreenshotApp/Views/MenuBarView.swift}"
PRIVACY="${5:-PRIVACY.md}"
PUBLISH_SCRIPT="${6:-script/publish_release.sh}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if [[ ! -f "$file" ]] || ! /usr/bin/grep -Fq -- "$pattern" "$file"; then
    echo "RepositoryPublicationChecks: $failure" >&2
    exit 1
  fi
}

require_text "$README" "releases/latest/download/ScreenshotApp-Bogdan-macOS-Universal.zip" \
  "README has no stable download link"
require_text "$README" "Apple Silicon" "README does not mention Apple Silicon support"
require_text "$README" "Intel" "README does not mention Intel support"
require_text "$README" "docs/assets/shelf-demo.gif" "README has no shelf demonstration"
require_text "$README" "docs/assets/hotkey-demo.gif" "README has no hotkey demonstration"
require_text "$README" "docs/assets/editor-demo.gif" "README has no editor demonstration"
require_text "$README" "docs/assets/scroll-capture-demo.gif" "README has no scrolling-capture demonstration"
require_text "$README" "v0.5.4" "README does not name the current public version"
require_text "$README" "Запись экрана" "README does not explain the screen-recording permission"
require_text "$README" "Gatekeeper" "README does not explain the unsigned preview limitation"
require_text "$README" "приложение и доступный заголовок окна" \
  "README does not explain local capture-source metadata"
require_text "$README" "CaptureMetadataChecks.sh" "README omits the metadata verification command"
[[ -s docs/assets/shelf-demo.gif ]] || {
  echo "RepositoryPublicationChecks: shelf demonstration asset is missing" >&2
  exit 1
}
[[ -s docs/assets/hotkey-demo.gif ]] || {
  echo "RepositoryPublicationChecks: hotkey demonstration asset is missing" >&2
  exit 1
}
[[ -s docs/assets/editor-demo.gif ]] || {
  echo "RepositoryPublicationChecks: editor demonstration asset is missing" >&2
  exit 1
}
[[ -s docs/assets/scroll-capture-demo.gif ]] || {
  echo "RepositoryPublicationChecks: scrolling-capture demonstration asset is missing" >&2
  exit 1
}

require_text "$WORKFLOW" "runs-on: macos-15" "workflow does not use a supported macOS runner"
require_text "$WORKFLOW" "./script/build_release.sh" "workflow does not create a Universal release"
require_text "$PUBLISH_SCRIPT" "gh release create" "local release script does not publish tagged releases"
require_text "$WORKFLOW" "CaptureMetadataChecks.sh" "workflow does not verify capture metadata propagation"

require_text "$GITIGNORE" ".build/" "Swift build output is not ignored"
require_text "$GITIGNORE" "dist/" "local release output is not ignored"
require_text "$MENU_BAR" "Проверить обновления…" "the app has no visible update action"
require_text "$MENU_BAR" "updateService.checkForUpdates()" \
  "the update action is not connected to the in-app updater"
require_text "$PRIVACY" "заголовок активного окна" "privacy policy omits locally saved window titles"

echo "RepositoryPublicationChecks: OK"
