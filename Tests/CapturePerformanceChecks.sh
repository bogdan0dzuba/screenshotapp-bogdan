#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-Sources/ScreenshotApp/Models/AppModel.swift}"
HISTORY="${2:-Sources/ScreenshotApp/Services/HistoryStore.swift}"
SHELF="${3:-Sources/ScreenshotApp/Views/ShelfView.swift}"
LOADER="${4:-Sources/ScreenshotApp/Services/CaptureImageLoader.swift}"
EDITOR="${5:-Sources/ScreenshotApp/Models/EditorSession.swift}"
PINNED="${6:-Sources/ScreenshotApp/Windowing/PinnedImageController.swift}"
CAPTURE_SERVICE="${7:-Sources/ScreenshotApp/Services/CaptureService.swift}"
ACTIVITY_STATE="${8:-Sources/ScreenshotCore/Capture/CaptureActivityState.swift}"
REQUEST_STATE="${9:-Sources/ScreenshotCore/Images/ImageLoadRequestState.swift}"
DECODE_POLICY="${10:-Sources/ScreenshotCore/Images/ShelfPreviewDecodePolicy.swift}"
CORE_CHECKS="${11:-Tests/CoreChecks/main.swift}"

require_file() {
  local file="$1"
  local failure="$2"
  if [[ ! -f "$file" ]]; then
    echo "CapturePerformanceChecks: $failure" >&2
    exit 1
  fi
}

require_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if ! /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "CapturePerformanceChecks: $failure" >&2
    exit 1
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  if /usr/bin/grep -Fq "$pattern" "$file"; then
    echo "CapturePerformanceChecks: $failure" >&2
    exit 1
  fi
}

require_file "$LOADER" "background preview loader is missing"
require_file "$CAPTURE_SERVICE" "capture service is missing"
require_file "$ACTIVITY_STATE" "capture activity state machine is missing"
require_file "$REQUEST_STATE" "image request state machine is missing"
require_file "$DECODE_POLICY" "progressive preview decode policy is missing"
reject_text "$HISTORY" "try? reload()" "history still blocks hotkey registration during model initialization"
require_text "$HISTORY" "ImageFileMetadata.dimensions(at:" "history still decodes full screenshots just to read dimensions"
reject_text "$HISTORY" "NSImage(contentsOf:" "history still decodes full screenshots on the main actor"
require_text "$HISTORY" "func importCapture(" "capture import is missing"
require_text "$HISTORY" ") async throws -> CaptureItem" "capture import is still synchronous"
require_text "$HISTORY" "Task.detached(priority: .userInitiated)" "capture file work is still performed on the main actor"
require_text "$HISTORY" "throw HistoryStoreError.captureFolderChanged" "a stale capture destination still reports false success"
require_text "$HISTORY" "item.imageURL.deletingLastPathComponent()" "item sidecars are resolved against the mutable current folder"
require_text "$HISTORY" "CGImageDestinationCreateWithURL" "background PNG encoding still depends on AppKit image representations"
require_text "$HISTORY" "for url in createdURLs.reversed()" "a failed background import can leave partial managed files"
require_text "$MODEL" "let item = try await history.importCapture(" "ordinary capture does not await background import"
require_text "$MODEL" "source: request.source" "background import drops capture metadata"
require_text "$MODEL" "private func captureArea()" "area hotkey still waits for the external selector to launch"
require_text "$MODEL" "regionSelectionController.selectRegion(using: captureService)" "area hotkey does not show the in-process selector"
require_text "$MODEL" "captureService.write(selection.image" "selected frozen pixels are not handed to the background writer"
require_text "$CAPTURE_SERVICE" "SCScreenshotManager.captureImage(in:" "modern macOS still launches an external process for every selected region"
require_text "$CAPTURE_SERVICE" "runScreencapture(arguments:" "macOS 14 fallback for selected-region capture is missing"
require_text "$MODEL" "finishCaptureAndBeginImport" "the hotkey remains blocked during background import"
require_text "$MODEL" "captureActivity.canChangeStorage" "storage can still change while a capture is importing"
require_text "$MODEL" "CaptureResultOrder.sequenceToPresent" "an older slow import can still replace a newer capture"
require_text "$MODEL" "capturedAt: capturedAt" "history order still follows import completion instead of capture time"
require_text "$SHELF" "CaptureImageLoader" "shelf previews do not use the background loader"
reject_text "$SHELF" "NSImage(contentsOf: url)" "shelf body still opens full PNG files synchronously"
require_text "$SHELF" "ShelfPreviewDecodePolicy.plan" "shelf previews do not increase detail progressively while zooming"
require_text "$SHELF" "decodePlan.maximumPixelSize" "shelf previews ignore the bounded decode plan"
require_text "$LOADER" "private actor CaptureImageDecodeQueue" "preview decodes are not serialized"
require_text "$LOADER" "ImageLoadRequestState" "cancelled preview requests cannot be retried safely"
reject_text "$LOADER" "Task.detached" "cancelled preview tasks can still create overlapping large decodes"
require_text "$CORE_CHECKS" "checkCaptureActivityState" "capture/import overlap has no deterministic test"
require_text "$CORE_CHECKS" "checkCaptureResultOrder" "reverse import completion order has no deterministic test"
require_text "$CORE_CHECKS" "checkImageLoadRequestState" "preview cancellation and retry have no deterministic test"
require_text "$CORE_CHECKS" "checkShelfPreviewDecodePolicy" "extreme-aspect memory bounds have no deterministic test"
require_text "$EDITOR" "if !document.annotations.isEmpty" "new captures are still rendered a second time before the editor appears"
require_text "$PINNED" "func windowWillClose" "closed pinned images remain retained in memory"

echo "CapturePerformanceChecks: OK"
