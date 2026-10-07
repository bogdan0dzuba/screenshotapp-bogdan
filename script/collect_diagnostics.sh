#!/usr/bin/env bash
set -euo pipefail
# Run on the affected Mac shortly after reproducing the failed launch/hotkey.
REPORT="${1:-$PWD/ScreenshotApp-diagnostics.txt}"
{
  /usr/bin/sw_vers
  /usr/bin/uname -m
  /usr/bin/log show --last 30m --style compact --info \
    --predicate 'subsystem == "local.codex.ScreenshotApp"'
} > "$REPORT"
echo "Диагностика сохранена: $REPORT"
