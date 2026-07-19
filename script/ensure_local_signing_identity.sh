#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="ScreenshotApp Bogdan Local Signing"
KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"

certificate_sha1() {
  /usr/bin/security find-certificate -c "$IDENTITY_NAME" -Z "$KEYCHAIN_PATH" 2>/dev/null \
    | /usr/bin/awk '/SHA-1 hash:/ && !printed { print $3; printed = 1 }'
}

if [[ -f "$KEYCHAIN_PATH" ]]; then
  EXISTING_SHA1="$(certificate_sha1)"
  if [[ -n "$EXISTING_SHA1" ]]; then
    printf '%s\n' "$EXISTING_SHA1"
    exit 0
  fi
fi

TEMP_DIR="$(/usr/bin/mktemp -d /private/tmp/ScreenshotApp-signing.XXXXXX)"
cleanup() {
  if [[ "$TEMP_DIR" == /private/tmp/ScreenshotApp-signing.* ]]; then
    /bin/rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

P12_PASSWORD="$(/usr/bin/uuidgen)"
PRIVATE_KEY="$TEMP_DIR/private-key.pem"
CERTIFICATE="$TEMP_DIR/certificate.pem"
IDENTITY_ARCHIVE="$TEMP_DIR/identity.p12"

/usr/bin/openssl req \
  -new \
  -newkey rsa:2048 \
  -nodes \
  -x509 \
  -days 3650 \
  -subj "/CN=$IDENTITY_NAME/O=Bogdan Local Development" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  -keyout "$PRIVATE_KEY" \
  -out "$CERTIFICATE" \
  >/dev/null 2>&1

/usr/bin/openssl pkcs12 \
  -export \
  -inkey "$PRIVATE_KEY" \
  -in "$CERTIFICATE" \
  -name "$IDENTITY_NAME" \
  -passout "pass:$P12_PASSWORD" \
  -out "$IDENTITY_ARCHIVE"

/usr/bin/security import "$IDENTITY_ARCHIVE" \
  -k "$KEYCHAIN_PATH" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  >/dev/null

NEW_SHA1="$(certificate_sha1)"
if [[ -z "$NEW_SHA1" ]]; then
  echo "Не удалось создать локальную identity для подписи" >&2
  exit 1
fi

printf '%s\n' "$NEW_SHA1"
