import AppKit
import ScreenshotCore
import SwiftUI

struct ShelfView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var history: HistoryStore

    init(model: AppModel) {
        self.model = model
        _history = ObservedObject(wrappedValue: model.history)
    }

    var body: some View {
        Group {
            if model.shelfState == .collapsed {
                collapsedBody
            } else {
                expandedBody
            }
        }
        .shelfGlassSurface(isCollapsed: model.shelfState == .collapsed)
    }

    private var collapsedBody: some View {
        ZStack {
            collapsedDragSurface
            HStack(spacing: ShelfMetrics.collapsedContentSpacing) {
                shelfToggleButton
                Text("\(history.items.count)")
                    .font(.system(
                        size: ShelfMetrics.collapsedCountFontSize(for: history.items.count),
                        weight: .bold,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.white.opacity(0.94))
                    .frame(width: ShelfMetrics.collapsedCountWidth)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, ShelfMetrics.collapsedHorizontalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var collapsedDragSurface: some View {
        ShelfWindowDragHandle()
    }

    private var shelfToggleButton: some View {
        ZStack {
            Group {
                if model.shelfState == .collapsed {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 15, weight: .bold))
                } else {
                    Image(systemName: "chevron.down")
                }
            }
                .foregroundStyle(
                    model.shelfState == .collapsed
                        ? Color.white.opacity(0.96)
                        : Color.primary
                )
                .shadow(
                    color: model.shelfState == .collapsed ? .black.opacity(0.5) : .clear,
                    radius: 1,
                    y: 1
                )
                .allowsHitTesting(false)
            ShelfToggleDragControl(
                accessibilityLabel: model.shelfState == .collapsed ? "Развернуть полку" : "Свернуть полку",
                onClick: toggleShelf
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .shelfToggleHitTarget()
        .shelfFirstClickEnabled()
        .help(model.shelfState == .collapsed ? "Развернуть полку" : "Свернуть полку")
    }

    private func toggleShelf() {
        if model.shelfState == .collapsed {
            model.expandShelf()
        } else {
            model.collapseShelf()
        }
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.22)
            if let item = model.selectedItem {
                latest(item)
                Divider().opacity(0.22)
                historyList(selected: item)
            } else {
                emptyState
            }
            Divider().opacity(0.22)
            captureBar
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            shelfToggleButton
            Image(systemName: "rectangle.stack.fill")
                .foregroundStyle(.primary)
            Text("\(history.items.count)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text(model.hotKeyDescription)
                .font(.caption2.monospaced().weight(.medium))
                .foregroundStyle(.secondary)
            ShelfWindowDragHandle()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            SettingsLink {
                Image(systemName: "gearshape")
                    .shelfToggleHitTarget()
            }
            .buttonStyle(.plain)
            .shelfToggleHitTarget()
            .shelfFirstClickEnabled()
            .help("Настройки")
            Menu {
                Button("На 30 секунд") { model.hideShelf(for: 30) }
                Button("На 5 минут") { model.hideShelf(for: 300) }
                Button("До следующего снимка") { model.hideShelf(for: nil) }
            } label: {
                Image(systemName: "eye.slash")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
            .help("Временно скрыть")
            Button { model.clearHistory() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .help("Очистить историю")
                .disabled(history.items.isEmpty)
        }
        .padding(.horizontal, 6)
        .frame(height: ShelfMetrics.headerHeight)
    }

    private func latest(_ item: CaptureItem) -> some View {
        VStack(spacing: 4) {
            ZoomableCapturePreview(url: item.imageURL)
                .id(item.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .simultaneousGesture(TapGesture().onEnded { copyFromPreview(item) })
                .onDrag { ScreenshotTransfer.itemProvider(for: item.imageURL) }
                .contextMenu { contextMenu(for: item) }

            HStack(spacing: 4) {
                quickButton("Копировать", "doc.on.doc") { model.copy(item) }
                quickButton("Сохранить", "square.and.arrow.down") { model.saveAs(item) }
                quickButton("Править", "pencil.tip.crop.circle") { model.edit(item) }
                quickButton("Распознать текст", "text.viewfinder") { model.recognizeText(item) }
                quickButton("Закрепить", "pin") { model.pin(item) }
            }
            Text(model.statusMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, ShelfMetrics.expandedContentPadding)
        .padding(.vertical, 6)
        .frame(minHeight: 140, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private func copyFromPreview(_ item: CaptureItem) {
        model.select(item)
        model.copy(item)
    }

    private func historyList(selected: CaptureItem) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(history.items) { item in
                    CaptureRow(item: item, isSelected: item.id == selected.id) {
                        model.select(item)
                    }
                    .onDrag { ScreenshotTransfer.itemProvider(for: item.imageURL) }
                    .contextMenu { contextMenu(for: item) }
                }
            }
            .padding(ShelfMetrics.expandedContentPadding)
        }
        .frame(
            minHeight: ShelfMetrics.historyMinimumHeight,
            idealHeight: ShelfMetrics.historyIdealHeight,
            maxHeight: ShelfMetrics.historyMaximumHeight
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Здесь появятся последние снимки")
                .foregroundStyle(.secondary)
            Text(model.hotKeyDescription)
                .font(.title3.monospaced())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var captureBar: some View {
        HStack(spacing: 5) {
            captureButton("С прокруткой", "arrow.up.and.down.text.horizontal") {
                model.startScrollingCapture()
            }
            captureButton("Обычная область", "viewfinder") { model.capture(.area) }
            captureButton("Окно", "macwindow") { model.capture(.window) }
            captureButton("Экран", "rectangle.inset.filled") { model.capture(.fullScreen) }
            Spacer()
            captureButton("Открыть папку", "folder") {
                NSWorkspace.shared.open(model.preferences.captureFolder)
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, ShelfMetrics.expandedContentPadding)
        .frame(height: ShelfMetrics.captureBarHeight)
    }

    private func quickButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
        .frame(height: ShelfMetrics.quickActionHeight)
        .contentShape(Rectangle())
        .shelfFirstClickEnabled()
        .help(title)
        .accessibilityLabel(title)
    }

    private func captureButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func contextMenu(for item: CaptureItem) -> some View {
        Button("Копировать") { model.copy(item) }
        Button("Сохранить как…") { model.saveAs(item) }
        Button("Редактировать") { model.edit(item) }
        Button("Распознать текст") { model.recognizeText(item) }
        Button("Закрепить поверх окон") { model.pin(item) }
        Button("Показать в Finder") { model.reveal(item) }
        Divider()
        Button("Удалить", role: .destructive) { model.delete(item) }
    }
}

private struct ShelfGlassSurfaceModifier: ViewModifier {
    let isCollapsed: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
#if canImport(SwiftUI, _version: 7.0)
        if #available(macOS 26.0, *) {
            if isCollapsed {
                content
                    .environment(\.colorScheme, .dark)
                    .glassEffect(
                        .clear.interactive(),
                        in: Capsule()
                    )
                    .background(Color.black.opacity(reduceTransparency ? 0.78 : 0.24), in: Capsule())
            } else {
                let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                content
                    .glassEffect(.clear, in: shape)
            }
        } else {
            fallbackSurface(content: content)
        }
#else
        fallbackSurface(content: content)
#endif
    }

    @ViewBuilder
    private func fallbackSurface(content: Content) -> some View {
        if isCollapsed {
            content
                .environment(\.colorScheme, .dark)
                .background { fallbackBackground(shape: Capsule(), tintOpacity: 0.38) }
                .clipShape(Capsule())
        } else {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            content
                .environment(\.colorScheme, .dark)
                .background { fallbackBackground(shape: shape, tintOpacity: 0.28) }
                .clipShape(shape)
        }
    }

    private func fallbackBackground<S: InsettableShape>(shape: S, tintOpacity: Double) -> some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.black.opacity(reduceTransparency ? 0.78 : tintOpacity))
            shape.stroke(
                LinearGradient(
                    colors: [.white.opacity(0.46), .white.opacity(0.08), .white.opacity(0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
    }
}

private extension View {
    func shelfGlassSurface(isCollapsed: Bool) -> some View {
        modifier(ShelfGlassSurfaceModifier(isCollapsed: isCollapsed))
    }

    func shelfToggleHitTarget() -> some View {
        frame(
            width: ShelfMetrics.toggleHitTargetSize.width,
            height: ShelfMetrics.toggleHitTargetSize.height
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func shelfFirstClickEnabled() -> some View {
        if #available(macOS 15.0, *) {
            allowsWindowActivationEvents(true)
        } else {
            self
        }
    }
}

private struct CapturePreview: View {
    let url: URL

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ContentUnavailableView("Файл недоступен", systemImage: "exclamationmark.triangle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ZoomableCapturePreview: View {
    let image: NSImage?

    @State private var zoomScale = 1.0
    @State private var magnificationStartScale: Double?

    init(url: URL) {
        image = NSImage(contentsOf: url)
    }

    var body: some View {
        GeometryReader { proxy in
            if let image {
                let viewport = CanvasSize(
                    width: Double(proxy.size.width),
                    height: Double(proxy.size.height)
                )
                let fittedSize = EditorZoomPolicy.aspectFitSize(
                    image: CanvasSize(width: Double(image.size.width), height: Double(image.size.height)),
                    viewport: viewport
                )
                let maximumScale = EditorZoomPolicy.maximumShelfScale(
                    fittedSize: fittedSize,
                    viewport: viewport
                )
                let zoomedSize = EditorZoomPolicy.contentSize(
                    base: fittedSize,
                    scale: zoomScale,
                    maximumScale: maximumScale
                )

                ScrollView([.horizontal, .vertical]) {
                    zoomableImage(
                        image,
                        size: zoomedSize,
                        viewportSize: proxy.size,
                        maximumScale: maximumScale
                    )
                }
            } else {
                ContentUnavailableView("Файл недоступен", systemImage: "exclamationmark.triangle")
            }
        }
        .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func zoomableImage(
        _ image: NSImage,
        size: CanvasSize,
        viewportSize: CGSize,
        maximumScale: Double
    ) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: CGFloat(size.width), height: CGFloat(size.height))
            .frame(
                minWidth: viewportSize.width,
                minHeight: viewportSize.height,
                alignment: .center
            )
            .contentShape(Rectangle())
            .simultaneousGesture(magnificationGesture(maximumScale: maximumScale))
    }

    private func magnificationGesture(maximumScale: Double) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let startScale = magnificationStartScale ?? zoomScale
                if magnificationStartScale == nil {
                    magnificationStartScale = startScale
                }
                zoomScale = EditorZoomPolicy.scale(
                    startScale: startScale,
                    magnification: Double(value.magnification),
                    maximumScale: maximumScale
                )
            }
            .onEnded { value in
                let startScale = magnificationStartScale ?? zoomScale
                zoomScale = EditorZoomPolicy.scale(
                    startScale: startScale,
                    magnification: Double(value.magnification),
                    maximumScale: maximumScale
                )
                magnificationStartScale = nil
            }
    }
}

private struct CaptureRow: View {
    let item: CaptureItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CapturePreview(url: item.imageURL)
                    .frame(width: 78, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(CaptureTimestampFormatter.historyTitle(for: item.createdAt))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if let source = item.captureSource?.displayLabel {
                        Text(source)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(source)
                    }
                    Text("\(item.pixelWidth) × \(item.pixelHeight)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
            }
            .padding(5)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ShelfWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ShelfWindowDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct ShelfToggleDragControl: NSViewRepresentable {
    let accessibilityLabel: String
    let onClick: () -> Void

    func makeNSView(context: Context) -> ShelfToggleDragView {
        let view = ShelfToggleDragView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: ShelfToggleDragView, context: Context) {
        update(nsView)
    }

    private func update(_ view: ShelfToggleDragView) {
        view.onClick = onClick
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(accessibilityLabel)
    }
}

private final class ShelfToggleDragView: NSView {
    var onClick: (() -> Void)?
    private var gestureState: ShelfToggleGestureState?
    private var initialWindowOrigin: CGPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        gestureState = ShelfToggleGestureState(start: NSEvent.mouseLocation)
        initialWindowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard var gestureState, let initialWindowOrigin, let window else { return }
        let location = NSEvent.mouseLocation
        gestureState.update(to: location)
        self.gestureState = gestureState
        guard gestureState.didDrag else { return }
        window.setFrameOrigin(CGPoint(
            x: initialWindowOrigin.x + location.x - gestureState.start.x,
            y: initialWindowOrigin.y + location.y - gestureState.start.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        guard var gestureState else { return }
        gestureState.update(to: NSEvent.mouseLocation)
        self.gestureState = nil
        initialWindowOrigin = nil
        if gestureState.shouldToggleOnRelease {
            onClick?()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

private final class ShelfWindowDragView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
