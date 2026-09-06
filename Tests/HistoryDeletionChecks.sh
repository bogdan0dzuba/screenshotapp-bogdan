#!/usr/bin/env bash
set -euo pipefail

HISTORY_STORE="${1:-Sources/ScreenshotApp/Services/HistoryStore.swift}"
APP_MODEL="${2:-Sources/ScreenshotApp/Models/AppModel.swift}"

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if ! /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "HistoryDeletionChecks: $failure" >&2
    exit 1
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "HistoryDeletionChecks: $failure" >&2
    exit 1
  fi
}

reject_text "$HISTORY_STORE" "NSWorkspace.shared.recycle" \
  "deletion still waits for a known-denied system Trash operation"
reject_text "$HISTORY_STORE" "trashItem(at:" \
  "capture deletion still uses the failing FileManager trash operation"
require_text "$HISTORY_STORE" "fileManager.removeItem(at: url)" \
  "app-owned capture files are not deleted directly"
reject_text "$HISTORY_STORE" "HistoryDeletionDisposition" \
  "obsolete Trash fallback state still complicates the deletion path"
reject_text "$APP_MODEL" "try await history.delete" \
  "the delete button still adds an asynchronous scheduling delay"
require_text "$APP_MODEL" "try history.delete(item)" \
  "the delete button does not execute the direct deletion path"
require_text "$APP_MODEL" "presentDeletionError" \
  "deletion failures still use the unrelated screen-recording permission alert"
require_text "$APP_MODEL" 'alert.messageText = "Не удалось удалить скриншот"' \
  "deletion failures do not identify the failed operation"
require_text "$APP_MODEL" 'statusMessage = "Удалено"' \
  "successful immediate deletion has no concise status"

echo "HistoryDeletionChecks: OK"
