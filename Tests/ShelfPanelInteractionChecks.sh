#!/usr/bin/env bash
set -euo pipefail

CONTROLLER="${1:-Sources/ScreenshotApp/Windowing/ShelfPanelController.swift}"
SHELF_VIEW="${2:-Sources/ScreenshotApp/Views/ShelfView.swift}"

require_source() {
  local pattern="$1"
  local failure="$2"
  if ! /usr/bin/grep -Fq "$pattern" "$CONTROLLER"; then
    echo "ShelfPanelInteractionChecks: $failure" >&2
    exit 1
  fi
}

require_view() {
  local pattern="$1"
  local failure="$2"
  if ! /usr/bin/grep -Fq "$pattern" "$SHELF_VIEW"; then
    echo "ShelfPanelInteractionChecks: $failure" >&2
    exit 1
  fi
}

reject_view() {
  local pattern="$1"
  local failure="$2"
  if /usr/bin/grep -Fq "$pattern" "$SHELF_VIEW"; then
    echo "ShelfPanelInteractionChecks: $failure" >&2
    exit 1
  fi
}

require_toggle_before_window_controls() {
  local toggle_line
  local controls_line
  toggle_line="$(/usr/bin/grep -n '^[[:space:]]*shelfToggleButton$' "$SHELF_VIEW" | /usr/bin/tail -n 1 | /usr/bin/cut -d: -f1)"
  controls_line="$(/usr/bin/grep -n '^[[:space:]]*ShelfWindowControls(' "$SHELF_VIEW" | /usr/bin/head -n 1 | /usr/bin/cut -d: -f1)"
  if [[ -z "$toggle_line" || -z "$controls_line" || "$toggle_line" -ge "$controls_line" ]]; then
    echo "ShelfPanelInteractionChecks: shelf toggle moves when expanded instead of staying left of close" >&2
    exit 1
  fi
}

require_source ".nonactivatingPanel" "shelf panel activates the app before delivering the first click"
require_source ".titled" "expanded shelf has no native macOS title-bar controls"
require_source ".closable" "expanded shelf has no native close control"
require_source ".miniaturizable" "expanded shelf has no native minimize control"
require_source ".fullSizeContentView" "native controls add an opaque title bar above the glass shelf"
require_source "titlebarAppearsTransparent = true" "native title bar does not blend into the glass shelf"
require_source "titleVisibility = .hidden" "shelf wastes title-bar space on a duplicate app name"
require_source ".fullScreenPrimary" "green window control cannot enter full screen"
require_source "panel.styleMask.insert(.borderless)" \
  "collapsed shelf retains the native title-bar minimum height"
require_source "panel.styleMask.remove(.titled)" \
  "collapsed shelf does not return to its compact borderless chrome"
require_source "ShelfWindowChromePolicy.showsCustomControls" \
  "custom window controls are not hidden in compact shelf states"
require_source "setStandardWindowControlsVisible(false)" \
  "inactive native traffic lights remain visible as misleading gray dots"
require_source "panel.deminiaturize(nil)" "a minimized shelf cannot be restored from the menu bar"
require_source "func windowShouldClose" "closing the shelf destroys its recoverable window"
require_source "panel.orderOut(nil)" "closing the shelf does not hide its window"
require_source "becomesKeyOnlyIfNeeded = true" "shelf panel consumes the first click to become key"
require_source "override func acceptsFirstMouse(for event: NSEvent?) -> Bool" "hosting view does not accept the first click"
require_source "ShelfHostingView(" "first-click hosting view is not installed"
require_source "onClose: { [weak panel] in panel?.orderOut(nil) }" \
  "custom close control is not connected to the shelf window"
require_source "onMinimize: { [weak panel] in panel?.miniaturize(nil) }" \
  "custom minimize control is not connected to the shelf window"
require_source "onToggleFullScreen: { [weak self] in self?.toggleFullScreen(nil) }" \
  "custom full-screen control is not connected to the shelf window"
require_source "isMovableByWindowBackground = false" "window background steals screenshot drag gestures"
require_view "allowsWindowActivationEvents(true)" "SwiftUI toggle drops the activation click"
require_view "ShelfMetrics.toggleHitTargetSize" "shelf toggle does not use the tested square hit target"
require_view "ShelfWindowControls(" "expanded shelf has no custom macOS window controls"
require_toggle_before_window_controls
require_view '.padding(.leading, ShelfMetrics.collapsedHorizontalPadding)' \
  "expanded shelf toggle does not keep the collapsed leading coordinate"
require_view "Color.red" "close control is not visibly red when the app is inactive"
require_view "Color.yellow" "minimize control is not visibly yellow when the app is inactive"
require_view "Color.green" "full-screen control is not visibly green when the app is inactive"
require_view 'systemName: "xmark"' "close control has no visible close symbol"
require_view 'systemName: "minus"' "minimize control has no visible minimize symbol"
require_view 'systemName: "arrow.up.left.and.arrow.down.right"' \
  "full-screen control has no visible expansion symbol"
require_view '.frame(width: 12, height: 12)' "custom traffic lights are larger than native macOS controls"
require_view 'label: "Закрыть полку"' "close control has no accessibility label"
require_view 'label: "Свернуть окно"' "minimize control has no accessibility label"
require_view 'label: "Полноэкранный режим"' "full-screen control has no accessibility label"
require_view '.accessibilityLabel(label)' "custom controls do not expose their labels to accessibility"
require_view ".ignoresSafeArea(.container, edges: .top)" \
  "native title bar remains a separate opaque strip above the glass shelf"
require_view "shelfToggleHitTarget()" "shelf toggle only hit-tests the chevron pixels"
require_view "ShelfToggleDragControl" "shelf toggle cannot distinguish a click from a drag"
require_view "override func mouseDragged(with event: NSEvent)" "chevron does not track movement before deciding to toggle"
require_view "override func mouseUp(with event: NSEvent)" "chevron toggles before the click or drag gesture ends"
require_view "window.setFrameOrigin" "dragging the chevron does not move the shelf window"
require_view "ShelfToggleGestureState" "chevron forgets that a drag threshold was already crossed"
require_view "gestureState.update(to:" "chevron drag events bypass the tested gesture state"
require_view "NSEvent.mouseLocation" "chevron control does not measure pointer travel"
require_view "Button(action: onOpenSettings)" "expanded shelf has no working settings button"
require_view 'Image(systemName: "gearshape")' "settings button has no gear icon"
require_view "ShelfWindowDragHandle" "shelf has no explicit window drag region"
require_view "collapsedDragSurface" "collapsed shelf drag area is still limited to the count label"
require_view ".allowsHitTesting(false)" "collapsed count blocks the drag surface below it"
require_view '.font(.system(size: 15, weight: .bold))' "collapsed expand icon is still too small"
require_view "ShelfMetrics.collapsedCountFontSize(for: history.items.count)" "two-digit collapsed count does not use its compact font"
require_view ".lineLimit(1)" "collapsed capture count can still wrap to a second line"
require_view ".minimumScaleFactor(0.8)" "collapsed capture count cannot shrink within its fixed slot"
require_view "ShelfMetrics.collapsedCountWidth" "collapsed capture count has no guaranteed one-line width"
require_view "fallbackBackground(shape: Capsule(), tintOpacity: 0.38)" "fallback glass is still too dark"
require_view "adaptiveTintOpacity(maximum: 0.24)" "collapsed glass ignores the saved transparency"
reject_view "reduceTransparency ? 0.98 : 0.92" "collapsed shelf still has the old nearly opaque black scrim"
reject_view 'Label("Скриншоты"' "expanded shelf still spends header space on an obvious title"
require_view 'Image(systemName: "rectangle.stack.fill")' "expanded header has no compact history icon"
require_view 'foregroundStyle(Color.secondary)' "history icon is darker than the other header controls"
require_view 'Text("\(history.items.count)")' "expanded header has no prominent capture count"
require_view '.font(.system(size: 16, weight: .bold, design: .rounded))' "expanded capture count is not prominent"
require_view 'Text(model.hotKeyDescription)' "current capture hotkey is not shown beside the count"
require_view '.font(.system(size: 13, weight: .semibold, design: .monospaced))' "expanded hotkey remains too small to read"
require_view 'Text("v\(AppIdentity.versionDescription)")' "expanded shelf does not show the current app version"
require_view '.fixedSize(horizontal: true, vertical: false)' "expanded app version is truncated by window controls"
require_view '.help("Текущая версия: \(AppIdentity.versionDescription)")' "visible app version has no explanatory hover hint"
reject_view 'Text(title).font(.system(size: 9))' "quick actions still waste screenshot space on labels"
require_view '.labelStyle(.iconOnly)' "icon-only controls do not preserve semantic labels"
require_view '.accessibilityLabel(title)' "quick actions lost their full accessibility names"
require_view 'ShelfMetrics.quickActionHeight' "quick actions do not use the compact tested height"
require_view 'scrollCaptureButton' "scrolling capture has no dedicated visible control"
require_view 'Label("Снимок с прокруткой", systemImage: "arrow.up.and.down.text.horizontal")' "scrolling capture is hidden behind an unexplained icon"
require_view '.labelStyle(.titleAndIcon)' "scrolling capture label is not visibly rendered"
require_view '.help("Выделить область и сделать длинный снимок прокруткой")' "scrolling capture has no explanatory hover hint"
require_view 'ShelfMetrics.captureBarHeight' "bottom capture controls do not use the compact tested height"
require_view '.help("История снимков")' "history icon has no hover explanation"
require_view '.help("Открыть настройки")' "settings icon has no hover explanation"
require_view '.help("Временно скрыть полку")' "temporary-hide icon has no hover explanation"
require_view '.help("Очистить историю и переместить файлы в Корзину")' "history-delete icon has no hover explanation"
require_view 'CaptureTimestampFormatter.historyTitle' "history rows still use a relative time or file name"
require_view 'item.captureSource?.displayLabel' "history rows do not show the saved capture source"
reject_view 'Text(model.statusMessage)' "copy status still consumes screenshot space under the action icons"
reject_view '.frame(height: 250)' "fixed latest-capture height still prevents the preview from using resized space"
require_view '.layoutPriority(1)' "latest screenshot does not receive the freed shelf space"
require_view 'GeometryReader { proxy in' "preview and history do not share measured shelf space"
require_view 'ShelfSplitLayout.heights(' "shelf does not calculate a persistent preview/history split"
require_view 'ShelfSplitLayout.historyFraction(' "divider movement is not converted into a clamped history share"
require_view 'DragGesture(minimumDistance: 0)' "preview/history divider cannot be dragged"
require_view 'preferences.historyFraction' "preview/history proportion is not persisted"
require_view 'ShelfSplitLayout.dividerHeight' "divider has no stable full-width hit area"
require_view '.frame(width: 48, height: 4)' "preview/history divider remains too subtle"
require_view 'NSCursor.resizeUpDown' "divider does not show the vertical resize cursor"
reject_view 'maxHeight: ShelfMetrics.historyMaximumHeight' "history is still capped at 144 points"
require_view '.glassEffect(.regular, in: shape)' "expanded shelf does not use standard Liquid Glass"
reject_view '.glassEffect(.clear, in: shape)' "expanded shelf is still forced to extra-clear glass"
require_view 'transparency: model.preferences.shelfTransparency' "glass does not react to the saved transparency preference"
require_view '1 - transparency' "transparency preference is not mapped to the glass background"
reject_view '.opacity(model.preferences.shelfTransparency)' "transparency incorrectly fades text and controls"
require_view "ZoomableCapturePreview" "expanded shelf preview cannot be magnified"
require_view "ScrollView([.horizontal, .vertical])" "magnified shelf preview cannot be panned"
require_view "MagnifyGesture" "expanded shelf preview has no native trackpad pinch gesture"
require_view "private func zoomableImage(" "shelf magnification is attached to the scroll view instead of the image"
require_view ".contentShape(Rectangle())" "the full screenshot does not receive trackpad magnification"
require_view ".simultaneousGesture(TapGesture()" "zoomable preview swallows screenshot clicks"
require_view "copyFromPreview(item)" "clicking the large screenshot does not copy it"
require_view '.frame(width: 104, height: 66)' "history thumbnails remain too small to distinguish captures"

echo "ShelfPanelInteractionChecks: OK"
