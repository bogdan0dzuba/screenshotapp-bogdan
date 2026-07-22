#!/usr/bin/env bash
set -euo pipefail

KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"
RELEASE_IDENTITY_NAME="ScreenshotApp Bogdan Local Signing"
RELEASE_CERTIFICATE_SHA1="12894FED984452E3FC2AFFDA5758A65BAC1DD2D2"
MODE="${1:---require-release}"

if [[ "$MODE" != "--require-release" ]]; then
  echo "usage: $0 --require-release" >&2
  exit 2
fi

certificate_count() {
  /usr/bin/security find-certificate -c "$RELEASE_IDENTITY_NAME" -p "$KEYCHAIN_PATH" 2>/dev/null \
    | /usr/bin/grep -c 'BEGIN CERTIFICATE' || true
}

certificate_sha1() {
  /usr/bin/security find-certificate -c "$RELEASE_IDENTITY_NAME" -Z "$KEYCHAIN_PATH" 2>/dev/null \
    | /usr/bin/awk '/SHA-1 hash:/ && !printed { print $3; printed = 1 }'
}

if [[ "$(certificate_count)" != 1 ]]; then
  echo "Не найдена единственная identity $RELEASE_IDENTITY_NAME; подпись выпуска остановлена" >&2
  exit 1
fi

SIGNING_CERT_SHA1="$(certificate_sha1)"
if [[ "$SIGNING_CERT_SHA1" != "$RELEASE_CERTIFICATE_SHA1" ]]; then
  echo "Сертификат $RELEASE_IDENTITY_NAME изменился; подпись выпуска остановлена" >&2
  exit 1
fi

if ! /usr/bin/security find-key \
  -l "$RELEASE_IDENTITY_NAME" \
  -s \
  -t private \
  "$KEYCHAIN_PATH" \
  >/dev/null 2>&1; then
  echo "Для $RELEASE_IDENTITY_NAME отсутствует приватный ключ; подпись выпуска остановлена" >&2
  exit 1
fi

printf '%s\n' "$SIGNING_CERT_SHA1"
