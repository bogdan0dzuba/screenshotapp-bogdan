#!/usr/bin/env bash
set -euo pipefail

CANDIDATE="${1:-}"
APPCAST_SOURCE="${2:-}"

if [[ ! "$CANDIDATE" =~ ^[0-9]+$ ]]; then
  echo "Номер сборки должен быть непустым целым числом." >&2
  exit 2
fi
if [[ -z "$APPCAST_SOURCE" ]]; then
  echo "Не указан appcast для проверки номера сборки." >&2
  exit 2
fi

APPCAST_FILE="$APPCAST_SOURCE"
TEMP_DIR=""
cleanup() {
  if [[ -n "$TEMP_DIR" ]]; then
    /bin/rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

case "$APPCAST_SOURCE" in
  http://*|https://*)
    TEMP_DIR="$(mktemp -d /private/tmp/ScreenshotAppPublicAppcast.XXXXXX)"
    APPCAST_FILE="$TEMP_DIR/appcast.xml"
    /usr/bin/curl --fail --silent --show-error --location \
      "$APPCAST_SOURCE" \
      --output "$APPCAST_FILE"
    ;;
esac

if [[ ! -f "$APPCAST_FILE" ]]; then
  echo "Appcast не найден: $APPCAST_SOURCE" >&2
  exit 2
fi

PUBLIC_BUILD="$(
  /usr/bin/xmllint \
    --xpath \
    'normalize-space(string((//*[local-name()="item"])[1]/*[local-name()="version"][1]))' \
    "$APPCAST_FILE" \
    2>/dev/null
)" || {
  echo "Не удалось прочитать первый sparkle:version из appcast." >&2
  exit 2
}

if [[ -z "$PUBLIC_BUILD" ]]; then
  PUBLIC_BUILD="$(
    /usr/bin/xmllint \
      --xpath \
      'normalize-space(string((//*[local-name()="item"])[1]/*[local-name()="enclosure"]/@*[local-name()="version"]))' \
      "$APPCAST_FILE" \
      2>/dev/null
  )" || {
    echo "Не удалось прочитать первый sparkle:version из appcast." >&2
    exit 2
  }
fi

if [[ ! "$PUBLIC_BUILD" =~ ^[0-9]+$ ]]; then
  echo "Первый sparkle:version в appcast отсутствует или не является числом." >&2
  exit 2
fi

CANDIDATE_NUMBER=$((10#$CANDIDATE))
PUBLIC_BUILD_NUMBER=$((10#$PUBLIC_BUILD))
if (( CANDIDATE_NUMBER <= PUBLIC_BUILD_NUMBER )); then
  echo "Номер сборки $CANDIDATE должен быть больше публичного $PUBLIC_BUILD." >&2
  exit 1
fi

printf '%s\n' "$CANDIDATE"
