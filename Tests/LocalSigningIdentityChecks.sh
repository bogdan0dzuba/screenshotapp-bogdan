#!/usr/bin/env bash
set -euo pipefail

IDENTITY_SCRIPT="${1:-script/ensure_local_signing_identity.sh}"

SHA1="$($IDENTITY_SCRIPT)"
if [[ ! "$SHA1" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "LocalSigningIdentityChecks: helper did not return one certificate SHA-1" >&2
  exit 1
fi

echo "LocalSigningIdentityChecks: OK"
