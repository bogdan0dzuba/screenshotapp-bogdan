#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Использование: ./script/publish_release.sh 0.5.3" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY="bogdan0dzuba/screenshotapp-bogdan"
TAG="v$VERSION"
SPARKLE_BIN_DIR="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
DIST_DIR="$ROOT_DIR/dist"

cd "$ROOT_DIR"

[[ "$(git branch --show-current)" == "main" ]] || {
  echo "Релиз можно публиковать только из ветки main." >&2
  exit 1
}
[[ -z "$(git status --porcelain)" ]] || {
  echo "Перед релизом рабочее дерево должно быть чистым." >&2
  exit 1
}

gh auth status --hostname github.com >/dev/null
git fetch origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || {
  echo "Локальная main не совпадает с origin/main." >&2
  exit 1
}

SCREENSHOT_APP_VERSION="$VERSION" "$ROOT_DIR/script/build_release.sh"

GENERATE_KEYS="$SPARKLE_BIN_DIR/generate_keys"
GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"
[[ -x "$GENERATE_KEYS" && -x "$GENERATE_APPCAST" ]] || {
  echo "Инструменты Sparkle не найдены после сборки." >&2
  exit 1
}

SPARKLE_TEMP_DIR="$(mktemp -d /private/tmp/ScreenshotAppSparkleRelease.XXXXXX)"
SPARKLE_PRIVATE_FILE="$SPARKLE_TEMP_DIR/private-key"
cleanup() {
  if [[ -n "${SPARKLE_PRIVATE_FILE:-}" && -f "$SPARKLE_PRIVATE_FILE" ]]; then
    unlink "$SPARKLE_PRIVATE_FILE"
  fi
  rmdir "$SPARKLE_TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

"$GENERATE_KEYS" -x "$SPARKLE_PRIVATE_FILE" >/dev/null
"$GENERATE_APPCAST" \
  --ed-key-file "$SPARKLE_PRIVATE_FILE" \
  --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
  --link "https://github.com/$REPOSITORY" \
  --maximum-versions 1 \
  "$DIST_DIR"
unlink "$SPARKLE_PRIVATE_FILE"
SPARKLE_PRIVATE_FILE=""

/usr/bin/grep -Fq 'sparkle:edSignature' "$DIST_DIR/appcast.xml" || {
  echo "Подписанный appcast.xml не создан." >&2
  exit 1
}

if git rev-parse "$TAG" >/dev/null 2>&1; then
  [[ "$(git rev-list -n 1 "$TAG")" == "$(git rev-parse HEAD)" ]] || {
    echo "Тег $TAG уже указывает на другой коммит." >&2
    exit 1
  }
else
  git tag -a "$TAG" -m "ScreenshotApp Bogdan $TAG"
fi
git push origin "$TAG"

RELEASE_ASSETS=(
  "$DIST_DIR/ScreenshotApp-Bogdan-macOS-Universal.zip"
  "$DIST_DIR/ScreenshotApp-Bogdan-macOS-Universal.zip.sha256"
  "$DIST_DIR/appcast.xml"
)

if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
  gh release upload "$TAG" "${RELEASE_ASSETS[@]}" --clobber --repo "$REPOSITORY"
else
  gh release create "$TAG" "${RELEASE_ASSETS[@]}" \
    --repo "$REPOSITORY" \
    --verify-tag \
    --title "ScreenshotApp Bogdan $TAG" \
    --generate-notes
fi

echo "Релиз опубликован: https://github.com/$REPOSITORY/releases/tag/$TAG"
