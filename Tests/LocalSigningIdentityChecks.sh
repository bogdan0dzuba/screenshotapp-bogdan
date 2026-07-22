#!/usr/bin/env bash
set -euo pipefail

IDENTITY_SCRIPT="${1:-script/ensure_local_signing_identity.sh}"
IDENTITY_MODE="${2:---require-release}"
RELEASE_CERTIFICATE_SHA1="12894FED984452E3FC2AFFDA5758A65BAC1DD2D2"

require_source() {
  local pattern="$1"
  local failure="$2"
  if [[ ! -f "$IDENTITY_SCRIPT" ]] || ! /usr/bin/grep -Fq -- "$pattern" "$IDENTITY_SCRIPT"; then
    echo "LocalSigningIdentityChecks: $failure" >&2
    exit 1
  fi
}

require_source 'RELEASE_CERTIFICATE_SHA1="12894FED984452E3FC2AFFDA5758A65BAC1DD2D2"' \
  "helper does not pin the permanent release certificate"
require_source 'security find-key' \
  "helper accepts a certificate whose private key is missing"
require_source '--require-release' \
  "helper cannot protect release builds from silently changing signing identity"

SHA1="$($IDENTITY_SCRIPT "$IDENTITY_MODE")"
if [[ ! "$SHA1" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "LocalSigningIdentityChecks: helper did not return one certificate SHA-1" >&2
  exit 1
fi

if [[ "$IDENTITY_MODE" == "--require-release" && "$SHA1" != "$RELEASE_CERTIFICATE_SHA1" ]]; then
  echo "LocalSigningIdentityChecks: helper returned a changed release certificate" >&2
  exit 1
fi

echo "LocalSigningIdentityChecks: OK"
