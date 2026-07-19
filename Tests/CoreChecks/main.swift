import AppKit
import CoreGraphics
import Foundation
import ScreenshotCore
import UniformTypeIdentifiers

private enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.failed(message) }
}

private func checkModels() throws {
    let annotation = Annotation.rectangle(
        NormalizedRect(x: 0.1, y: 0.2, width: 0.4, height: 0.3),
        style: .init(color: .red, lineWidth: 5)
    )
    let value = EditorDocument(
        imageFileName: "capture.png",
        canvasSize: CanvasSize(width: 120, height: 80),
        annotations: [annotation]
    )
    let decoded = try JSONDecoder().decode(EditorDocument.self, from: JSONEncoder().encode(value))
    try expect(decoded == value, "EditorDocument JSON round-trip")

    let source = CaptureSource(
        applicationName: "Safari",
        windowTitle: "https://www.example.com/orders?status=new"
    )
    let sourcedDocument = EditorDocument(
        imageFileName: "capture.png",
        canvasSize: CanvasSize(width: 120, height: 80),
        annotations: [annotation],
        captureSource: source
    )
    let sourcedDecoded = try JSONDecoder().decode(
        EditorDocument.self,
        from: JSONEncoder().encode(sourcedDocument)
    )
    try expect(sourcedDecoded.captureSource == source, "capture source survives project JSON round-trip")

    let legacyJSON = Data(#"{"imageFileName":"legacy.png","canvasSize":{"width":40,"height":30},"annotations":[]}"#.utf8)
    let legacyDocument = try JSONDecoder().decode(EditorDocument.self, from: legacyJSON)
    try expect(legacyDocument.captureSource == nil, "legacy project JSON remains decodable")

    try expect(
        source.displayLabel == "Safari · example.com",
        "explicit browser URL is shortened to an app and host"
    )
    try expect(
        CaptureSource(
            applicationName: "Google Chrome",
            windowTitle: "Заказы - Google Chrome"
        ).displayLabel == "Google Chrome · Заказы",
        "browser suffix is removed from a window title"
    )
    try expect(
        CaptureSource(applicationName: "Telegram", windowTitle: nil).displayLabel == "Telegram",
        "application name is used when the window title is unavailable"
    )
    let computerUseControls = CaptureSource(
        applicationName: "ChatGPT",
        windowTitle: "Computer Use Controls"
    )
    try expect(
        computerUseControls.isComputerUseControlWindow,
        "ChatGPT computer-use controls are recognized as a transient capture overlay"
    )
    try expect(
        computerUseControls.withoutWindowTitle.displayLabel == "ChatGPT",
        "computer-use fallback does not preserve a misleading controls title"
    )

    let now = Date(timeIntervalSince1970: 2_000_000)
    let fixtures = (0..<3).map { offset in
        CaptureItem(
            id: UUID(),
            createdAt: now.addingTimeInterval(TimeInterval(offset - 2) * 60),
            imageURL: URL(fileURLWithPath: "/tmp/\(offset).png"),
            projectURL: nil,
            pixelWidth: 100,
            pixelHeight: 80
        )
    }
    let result = HistoryIndex.pruned(items: fixtures, maximumCount: 2, maximumAgeDays: 30, now: now)
    try expect(result.map(\.id) == [fixtures[2].id, fixtures[1].id], "history ordering and count")

    let old = CaptureItem(
        id: UUID(),
        createdAt: now.addingTimeInterval(-31 * 86_400),
        imageURL: URL(fileURLWithPath: "/tmp/old.png"),
        projectURL: nil,
        pixelWidth: 1,
        pixelHeight: 1
    )
    try expect(HistoryIndex.pruned(items: [old], maximumCount: 200, maximumAgeDays: 30, now: now).isEmpty, "history age")
    try expect(HotKey.defaultCapture.key == "A", "default hotkey key")
    try expect(HotKey.defaultCapture.modifiers == [.command, .shift], "default hotkey modifiers")
}

private func checkHotKeyFormatting() throws {
    let hotKey = HotKey(key: "A", keyCode: 0, modifiers: [.command, .shift])
    try expect(
        HotKeyDisplayFormatter.symbolic(hotKey) == "⌘⇧A",
        "shortcut symbols put Command before Shift"
    )
    try expect(
        HotKeyDisplayFormatter.readable(hotKey) == "Command (⌘) + Shift (⇧) + A",
        "shortcut has an explicit human-readable form"
    )
}

private func checkEditorState() throws {
    var state = EditorState(document: .empty)
    let layer = Annotation.line(
        from: .zero,
        to: NormalizedPoint(x: 1, y: 1),
        style: .init(color: .red)
    )
    state.add(layer)
    try expect(state.document.annotations == [layer], "editor adds a layer")
    state.undo()
    try expect(state.document.annotations.isEmpty, "editor undo")
    state.redo()
    try expect(state.document.annotations == [layer], "editor redo")
    state.select(layer.id)
    state.deleteSelected()
    try expect(state.document.annotations.isEmpty, "editor deletes selected layer")
}

private func checkOverlapMatching() throws {
    let first = GrayImage(
        width: 3,
        height: 6,
        pixels: [0, 0, 0, 10, 10, 10, 20, 20, 20, 30, 30, 30, 40, 40, 40, 50, 50, 50]
    )
    let second = GrayImage(
        width: 3,
        height: 6,
        pixels: [30, 30, 30, 40, 40, 40, 50, 50, 50, 60, 60, 60, 70, 70, 70, 80, 80, 80]
    )
    let overlap = try OverlapMatcher.bestVerticalOverlap(previous: first, next: second)
    try expect(overlap == 3, "scroll overlap")

    let match = try OverlapMatcher.bestVerticalMatch(previous: first, next: second)
    try expect(match.overlap == 3, "scroll match reports overlap")
    try expect(match.meanDifference == 0, "scroll match reports confidence")
}

private func checkAutomaticScrollFrameSelection() throws {
    let first = GrayImage(
        width: 3,
        height: 6,
        pixels: [0, 0, 0, 10, 10, 10, 20, 20, 20, 30, 30, 30, 40, 40, 40, 50, 50, 50]
    )
    let shifted = GrayImage(
        width: 3,
        height: 6,
        pixels: [30, 30, 30, 40, 40, 40, 50, 50, 50, 60, 60, 60, 70, 70, 70, 80, 80, 80]
    )
    let unrelated = GrayImage(
        width: 3,
        height: 6,
        pixels: [200, 10, 180, 5, 210, 20, 190, 15, 220, 0, 205, 25, 185, 30, 215, 35, 195, 40]
    )
    let policy = ScrollFramePolicy(
        minimumNewRows: 2,
        minimumOverlapRows: 2,
        maximumMeanDifference: 20
    )

    let duplicateDecision = try ScrollFrameClassifier.decision(previous: first, next: first, policy: policy)
    let shiftedDecision = try ScrollFrameClassifier.decision(previous: first, next: shifted, policy: policy)
    let reverseDecision = try ScrollFrameClassifier.decision(previous: shifted, next: first, policy: policy)
    let unrelatedDecision = try ScrollFrameClassifier.decision(previous: first, next: unrelated, policy: policy)
    try expect(duplicateDecision == .unchanged, "automatic scroll capture skips duplicate frames")
    try expect(
        shiftedDecision == .append(overlap: 3),
        "automatic scroll capture accepts a changed overlapping frame"
    )
    try expect(
        reverseDecision == .prepend(overlap: 3),
        "automatic scroll capture accepts upward scrolling"
    )
    try expect(
        unrelatedDecision == .insufficientOverlap,
        "automatic scroll capture rejects a frame that cannot be stitched"
    )
}

private func checkCaptureCompletionPolicy() throws {
    try expect(CaptureCompletionPolicy.standard.opensEditor, "a finished screenshot opens the editor")
    try expect(CaptureCompletionPolicy.standard.revealsShelf, "a finished screenshot remains available on the shelf")
}

private func checkCaptureProcessOutcome() throws {
    try expect(
        CaptureProcessOutcome.resolve(terminationStatus: 0, outputExists: false) == .cancelled,
        "Escape cancellation is silent when screencapture exits successfully without an image"
    )
    try expect(
        CaptureProcessOutcome.resolve(terminationStatus: 0, outputExists: true) == .success,
        "a successful screencapture with an image is accepted"
    )
    try expect(
        CaptureProcessOutcome.resolve(terminationStatus: 2, outputExists: false) == .failed(2),
        "a real screencapture failure remains visible"
    )
}

private func checkEditorCanvasLayout() throws {
    let tall = EditorCanvasLayout.contentSize(
        image: CanvasSize(width: 1_000, height: 5_000),
        availableWidth: 900,
        horizontalPadding: 42
    )
    try expect(abs(tall.width - 816) < 0.001, "long screenshots fit editor width")
    try expect(abs(tall.height - 4_080) < 0.001, "long screenshots keep their readable aspect ratio")
    try expect(tall.height > 700, "long screenshots remain scrollable instead of becoming unreadably small")

    let small = EditorCanvasLayout.contentSize(
        image: CanvasSize(width: 320, height: 240),
        availableWidth: 900,
        horizontalPadding: 42
    )
    try expect(small == CanvasSize(width: 320, height: 240), "small screenshots are not enlarged")

    let compactWindow = EditorWindowLayout.contentSize(
        image: CanvasSize(width: 20, height: 20),
        visibleSize: CanvasSize(width: 1_440, height: 900)
    )
    try expect(
        compactWindow == CanvasSize(width: 440, height: 320),
        "tiny screenshots open in a compact usable editor"
    )

    let normalWindow = EditorWindowLayout.contentSize(
        image: CanvasSize(width: 800, height: 600),
        visibleSize: CanvasSize(width: 1_440, height: 900)
    )
    try expect(
        normalWindow == CanvasSize(width: 936, height: 776),
        "editor window follows the screenshot dimensions"
    )

    let oversizedWindow = EditorWindowLayout.contentSize(
        image: CanvasSize(width: 4_000, height: 3_000),
        visibleSize: CanvasSize(width: 1_440, height: 900)
    )
    try expect(
        oversizedWindow.width <= 1_296 && oversizedWindow.height <= 810,
        "editor window remains inside the visible screen"
    )
}

private func checkEditorZoomPolicy() throws {
    try expect(
        EditorZoomPolicy.scale(startScale: 1, magnification: 1.5) == 1.5,
        "trackpad magnification enlarges the editor canvas"
    )
    try expect(
        EditorZoomPolicy.scale(startScale: 2, magnification: 0.5) == 1,
        "trackpad magnification reduces the editor canvas"
    )
    try expect(
        EditorZoomPolicy.scale(startScale: 1, magnification: 0.01) == 0.25,
        "editor zoom has a readable minimum"
    )
    try expect(
        EditorZoomPolicy.scale(startScale: 4, magnification: 10) == 8,
        "editor zoom has a safe maximum"
    )
    try expect(
        EditorZoomPolicy.contentSize(
            base: CanvasSize(width: 816, height: 4_080),
            scale: 1.5
        ) == CanvasSize(width: 1_224, height: 6_120),
        "zoom preserves the screenshot aspect ratio"
    )
    try expect(
        EditorZoomPolicy.aspectFitSize(
            image: CanvasSize(width: 1_000, height: 5_000),
            viewport: CanvasSize(width: 600, height: 150)
        ) == CanvasSize(width: 30, height: 150),
        "shelf preview starts fully fitted inside its viewport"
    )
    try expect(
        EditorZoomPolicy.maximumShelfScale(
            fittedSize: CanvasSize(width: 30, height: 150),
            viewport: CanvasSize(width: 600, height: 150)
        ) == 20,
        "long shelf screenshots can zoom until their width fills the viewport"
    )
    try expect(
        EditorZoomPolicy.scale(startScale: 10, magnification: 3, maximumScale: 20) == 20,
        "shelf preview honors its content-aware maximum zoom"
    )
}

private func checkShelfSplitLayout() throws {
    try expect(
        ShelfSplitLayout.historyFraction(-1) == ShelfSplitLayout.minimumHistoryFraction,
        "history fraction clamps below its minimum"
    )
    try expect(
        ShelfSplitLayout.historyFraction(2) == ShelfSplitLayout.maximumHistoryFraction,
        "history fraction clamps above its maximum"
    )

    let regular = ShelfSplitLayout.heights(
        availableHeight: 500,
        historyFraction: ShelfSplitLayout.defaultHistoryFraction
    )
    try expect(
        regular.latest + regular.history + ShelfSplitLayout.dividerHeight == 500,
        "shelf split consumes all available height"
    )
    try expect(
        abs(regular.history - 205.8) < 0.000_001,
        "default shelf split gives history forty-two percent of content"
    )

    let constrained = ShelfSplitLayout.heights(availableHeight: 230, historyFraction: 1)
    try expect(constrained.latest == 140, "small shelf preserves the latest-capture minimum")
    try expect(constrained.history == 80, "small shelf preserves the history minimum")

    try expect(
        abs(ShelfSplitLayout.historyFraction(
            startingFraction: 0.3,
            verticalTranslation: -50,
            availableHeight: 500
        ) - 0.4) < 0.000_001,
        "dragging the divider upward gives more room to history"
    )
    try expect(
        abs(ShelfSplitLayout.historyFraction(
            startingFraction: 0.3,
            verticalTranslation: 50,
            availableHeight: 500
        ) - 0.2) < 0.000_001,
        "dragging the divider downward gives more room to the preview"
    )
}

private func makeGrayImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
        throw CheckFailure.failed("fixture CGImage")
    }
    return image
}

private func checkScrollStitching() throws {
    let first = try makeGrayImage(width: 2, height: 4, pixels: [0, 0, 10, 10, 20, 20, 30, 30])
    let second = try makeGrayImage(width: 2, height: 4, pixels: [20, 20, 30, 30, 40, 40, 50, 50])
    let output = try ScrollStitcher.stitch([first, second])
    try expect(output.width == 2, "stitched width")
    try expect(output.height == 6, "stitched height without duplicate rows")
}

private func makeColorImage(width: Int, height: Int) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CheckFailure.failed("fixture RGB context")
    }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else { throw CheckFailure.failed("fixture RGB image") }
    return image
}

private func checkAnnotationRendering() throws {
    let image = try makeColorImage(width: 32, height: 24)
    let document = EditorDocument(
        imageFileName: "fixture.png",
        canvasSize: CanvasSize(width: 32, height: 24),
        annotations: [
            .rectangle(
                NormalizedRect(x: 0.1, y: 0.1, width: 0.6, height: 0.5),
                style: .init(color: .red, lineWidth: 3)
            )
        ]
    )
    let output = try AnnotationRenderer.render(baseImage: image, document: document)
    try expect(output.width == 32 && output.height == 24, "annotation renderer size")
}

private func checkShelfState() throws {
    var collapsed = ShelfState.collapsed
    collapsed.receivedNewCapture()
    try expect(collapsed == .collapsed, "new capture preserves a deliberately collapsed shelf")

    var expanded = ShelfState.expanded
    expanded.receivedNewCapture()
    try expect(expanded == .expanded, "new capture preserves an expanded shelf")

    var hidden = ShelfState.hiddenUntilNextCapture
    hidden.receivedNewCapture()
    try expect(hidden == .collapsed, "next capture reveals a hidden shelf without expanding it")
}

private func checkScrollSession() throws {
    let above = try makeGrayImage(width: 2, height: 4, pixels: [0, 0, 10, 10, 20, 20, 30, 30])
    let middle = try makeGrayImage(width: 2, height: 4, pixels: [20, 20, 30, 30, 40, 40, 50, 50])
    let below = try makeGrayImage(width: 2, height: 4, pixels: [40, 40, 50, 50, 60, 60, 70, 70])
    var session = ScrollCaptureSession(frames: [middle])
    session.add(below, direction: .down)
    session.add(above, direction: .up)
    try expect(session.frames.first === above, "upward scroll frames are prepended")
    try expect(session.latestFrame === above, "scroll comparison follows capture order")
    session.undoLastFrame()
    try expect(session.frames.count == 2, "scroll session removes the most recently captured frame")
    try expect(session.latestFrame === below, "undo restores the previous observed frame")
    let output = try session.finish()
    try expect(output.height == 6, "scroll session finishes stitched image")
}

private func checkOCRTextOrdering() throws {
    let text = OCRTextFormatter.join(lines: [
        RecognizedLine(text: "два", minX: 0.1, midY: 0.2),
        RecognizedLine(text: "один", minX: 0.1, midY: 0.8),
    ])
    try expect(text == "один\nдва", "OCR text order")
}

private func checkShelfPlacementOnSecondaryDisplay() throws {
    let secondaryVisibleFrame = CGRect(x: 1_512, y: 0, width: 1_512, height: 982)
    let expandedFrame = CGRect(x: 1_820, y: 40, width: 380, height: 520)
    let collapsedFrame = ShelfPlacement.resizedFrame(
        currentFrame: expandedFrame,
        targetSize: ShelfMetrics.collapsedSize,
        visibleFrame: secondaryVisibleFrame,
        hasBeenPresented: true
    )

    try expect(collapsedFrame.minX == expandedFrame.minX, "shelf keeps its left edge on a secondary display")
    try expect(collapsedFrame.maxY == expandedFrame.maxY, "shelf toggle keeps its top edge while collapsing")

    let restoredFrame = ShelfPlacement.resizedFrame(
        currentFrame: collapsedFrame,
        targetSize: expandedFrame.size,
        visibleFrame: secondaryVisibleFrame,
        hasBeenPresented: true
    )
    try expect(restoredFrame.minX == collapsedFrame.minX, "expanded shelf keeps the toggle horizontal position")
    try expect(restoredFrame.maxY == collapsedFrame.maxY, "expanded shelf keeps the toggle vertical position")

    let edgeCollapsedFrame = CGRect(
        x: secondaryVisibleFrame.maxX - ShelfMetrics.collapsedSize.width,
        y: secondaryVisibleFrame.maxY - ShelfMetrics.collapsedSize.height,
        width: ShelfMetrics.collapsedSize.width,
        height: ShelfMetrics.collapsedSize.height
    )
    let edgeExpandedFrame = ShelfPlacement.resizedFrame(
        currentFrame: edgeCollapsedFrame,
        targetSize: CGSize(width: 520, height: 620),
        visibleFrame: secondaryVisibleFrame,
        hasBeenPresented: true
    )
    try expect(edgeExpandedFrame.minX == edgeCollapsedFrame.minX, "right-edge toggle never moves horizontally")
    try expect(edgeExpandedFrame.maxY == edgeCollapsedFrame.maxY, "right-edge toggle never moves vertically")
}

private func checkCompactShelfMetrics() throws {
    try expect(
        ShelfMetrics.toggleHitTargetSize == CGSize(width: 28, height: 28),
        "shelf toggle exposes a full square hit target"
    )
    try expect(
        ShelfMetrics.collapsedSize == CGSize(width: 60, height: 34),
        "collapsed shelf is smaller while keeping room for the larger icon and count"
    )
    try expect(
        ShelfMetrics.collapsedCountFontSize(for: 9) == 14,
        "a one-digit collapsed count stays prominent"
    )
    try expect(
        ShelfMetrics.collapsedCountFontSize(for: 10) == 12,
        "a two-digit collapsed count uses the compact font"
    )
    let collapsedContentWidth = ShelfMetrics.collapsedHorizontalPadding * 2
        + ShelfMetrics.toggleHitTargetSize.width
        + ShelfMetrics.collapsedContentSpacing
        + ShelfMetrics.collapsedCountWidth
    try expect(
        collapsedContentWidth <= ShelfMetrics.collapsedSize.width,
        "the toggle and a fixed-width two-digit count fit on one line"
    )
    try expect(
        ShelfMetrics.expandedSize == CGSize(width: 380, height: 520),
        "expanded shelf keeps its working size"
    )
    try expect(ShelfMetrics.headerHeight == 32, "compact shelf header uses only necessary vertical space")
    try expect(ShelfMetrics.quickActionHeight == 28, "icon-only quick actions stay compact")
    try expect(ShelfMetrics.captureBarHeight == 30, "capture bar leaves more room for screenshots")
    try expect(
        ShelfMetrics.constrainedExpandedSize(
            CGSize(width: 640, height: 700),
            visibleSize: CGSize(width: 1_200, height: 900)
        ) == CGSize(width: 640, height: 700),
        "user-selected expanded size is preserved"
    )
    try expect(
        ShelfMetrics.constrainedExpandedSize(
            CGSize(width: 100, height: 100),
            visibleSize: CGSize(width: 1_200, height: 900)
        ) == ShelfMetrics.minimumExpandedSize,
        "expanded shelf enforces a usable minimum"
    )
}

private func checkShelfToggleGesturePolicy() throws {
    try expect(
        ShelfToggleGesturePolicy.shouldToggle(
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 12, y: 12)
        ),
        "short pointer movement remains a toggle click"
    )
    try expect(
        !ShelfToggleGesturePolicy.shouldToggle(
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 18, y: 10)
        ),
        "dragging the toggle moves the shelf without expanding it"
    )

    var gesture = ShelfToggleGestureState(start: CGPoint(x: 10, y: 10))
    gesture.update(to: CGPoint(x: 18, y: 10))
    gesture.update(to: CGPoint(x: 10, y: 10))
    try expect(
        !gesture.shouldToggleOnRelease,
        "crossing the drag threshold permanently suppresses toggle for that gesture"
    )
}

private func checkShelfWindowSizeStorage() throws {
    let suiteName = "ScreenshotApp.CoreChecks.ShelfSize.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw CheckFailure.failed("isolated UserDefaults suite")
    }
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = ShelfWindowSizeStore(defaults: defaults)
    try expect(store.load() == ShelfMetrics.expandedSize, "expanded shelf size starts at the default")
    store.save(CGSize(width: 612, height: 734))
    try expect(store.load() == CGSize(width: 612, height: 734), "expanded shelf size survives a reload")

    try expect(
        !ShelfWindowResizePolicy.shouldPersist(
            isExpanded: true,
            isApplyingPresentation: false,
            isLiveResize: false
        ),
        "system layout changes never overwrite the preferred expanded size"
    )
    try expect(
        ShelfWindowResizePolicy.shouldPersist(
            isExpanded: true,
            isApplyingPresentation: false,
            isLiveResize: true
        ),
        "a user live-resize persists the preferred expanded size"
    )
}

private func checkScreenshotTransferPayloads() throws {
    let image = try makeColorImage(width: 12, height: 8)
    let representation = NSBitmapImageRep(cgImage: image)
    guard let pngData = representation.representation(using: .png, properties: [:]) else {
        throw CheckFailure.failed("fixture PNG data")
    }
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenshotTransfer-\(UUID().uuidString).png")
    try pngData.write(to: fileURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ScreenshotApp.CoreChecks.\(UUID().uuidString)"))
    try ScreenshotTransfer.writeImage(at: fileURL, to: pasteboard)
    let types = Set(pasteboard.types ?? [])
    try expect(types.contains(.png), "clipboard provides PNG")
    try expect(types.contains(.tiff), "clipboard provides TIFF")
    try expect(types.contains(.fileURL), "clipboard provides file URL")
    try expect(NSImage(pasteboard: pasteboard) != nil, "clipboard image can be pasted by AppKit applications")
    let pastedURLs = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
    try expect(pastedURLs?.first == fileURL, "clipboard file URL can be pasted by file-based applications")

    let provider = ScreenshotTransfer.itemProvider(for: fileURL)
    try expect(provider.hasItemConformingToTypeIdentifier(UTType.png.identifier), "drag provider supplies PNG file")
    try expect(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier), "drag provider supplies file URL")

    let loaded = DispatchSemaphore(value: 0)
    var loadedURL: URL?
    var loadError: Error?
    provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, _, error in
        loadedURL = url
        loadError = error
        loaded.signal()
    }
    try expect(loaded.wait(timeout: .now() + 2) == .success, "drag provider resolves promptly")
    try expect(loadError == nil, "drag provider resolves without error")
    try expect(loadedURL == fileURL, "drag provider resolves the real screenshot file")

    let loadedData = DispatchSemaphore(value: 0)
    var draggedPNG: Data?
    provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
        draggedPNG = data
        loadedData.signal()
    }
    try expect(loadedData.wait(timeout: .now() + 2) == .success, "drag provider resolves PNG data promptly")
    try expect(draggedPNG == pngData, "drag provider supplies the screenshot PNG bytes")
}

private func checkShelfCopyShortcuts() throws {
    try expect(
        ShelfKeyboardShortcut.isCopy(key: "c", modifiers: [.command]),
        "Command-C copies the selected capture"
    )
    try expect(
        ShelfKeyboardShortcut.isCopy(key: "C", modifiers: [.control]),
        "Control-C also copies the selected capture"
    )
    try expect(
        ShelfKeyboardShortcut.shouldCopy(
            key: "c",
            modifiers: [.control],
            eventWindowNumber: 42,
            panelWindowNumber: 42,
            panelIsKey: false
        ),
        "Control-C works when the shelf receives the event without becoming key"
    )
    try expect(
        ShelfKeyboardShortcut.isCopy(key: "\u{3}", keyCode: 8, modifiers: [.control]),
        "Control-C works when AppKit reports a control character"
    )
    try expect(
        !ShelfKeyboardShortcut.isCopy(key: "c", modifiers: [.option]),
        "Option-C is not treated as copy"
    )
}

private func checkCaptureTimestampFormatting() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 18,
        hour: 12,
        minute: 0
    ))!
    let recent = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 18,
        hour: 9,
        minute: 7,
        second: 42
    ))!

    try expect(
        CaptureTimestampFormatter.string(for: recent, now: now, calendar: calendar) == "09:07",
        "recent capture time contains hours and minutes only"
    )
    let historyDate = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 19,
        hour: 14,
        minute: 50,
        second: 37
    ))!
    try expect(
        CaptureTimestampFormatter.historyTitle(
            for: historyDate,
            calendar: calendar,
            locale: Locale(identifier: "ru_RU")
        ) == "19 июля, 14:50",
        "history title contains Russian date and time without seconds"
    )
    try expect(
        CaptureTimestampFormatter.string(
            for: now.addingTimeInterval(-(23 * 3_600 + 1)),
            now: now,
            calendar: calendar
        ) == "1 день",
        "capture older than 23 hours uses days"
    )
    try expect(
        CaptureTimestampFormatter.string(for: now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "1 день",
        "one-day-old capture uses days"
    )
    try expect(
        CaptureTimestampFormatter.string(for: now.addingTimeInterval(-2 * 86_400), now: now, calendar: calendar) == "2 дня",
        "two-day-old capture uses the Russian plural"
    )
    try expect(
        CaptureTimestampFormatter.string(for: now.addingTimeInterval(-5 * 86_400), now: now, calendar: calendar) == "5 дней",
        "five-day-old capture uses the Russian plural"
    )
}

private func checkHistoryRetentionPolicy() throws {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let fixtures = (0..<25).map { offset in
        CaptureItem(
            id: UUID(),
            createdAt: now.addingTimeInterval(TimeInterval(offset)),
            imageURL: URL(fileURLWithPath: "/tmp/retention-\(offset).png"),
            projectURL: nil,
            pixelWidth: 100,
            pixelHeight: 80
        )
    }
    let retained = HistoryIndex.pruned(
        items: fixtures,
        maximumCount: HistoryRetentionPolicy.maximumCaptures,
        maximumAgeDays: 30,
        now: now.addingTimeInterval(25)
    )

    try expect(HistoryRetentionPolicy.maximumCaptures == 20, "history policy keeps at most 20 captures")
    try expect(retained.count == 20, "history index enforces the 20-capture limit")
    try expect(retained.first?.id == fixtures.last?.id, "history index retains the newest capture first")
}

private func checkManagedCaptureFiles() throws {
    let captureID = "F39B9C8E-DAF8-4B1E-9959-C49DB159D35D"
    let fileName = "Снимок 2026-07-18 12.00.00-\(captureID).png"
    try expect(
        CaptureFileClassifier.isRenderedCapture(
            URL(fileURLWithPath: "/tmp/\(fileName)")
        ),
        "rendered ScreenshotApp capture is recognized"
    )
    try expect(
        CaptureFileClassifier.isManagedCaptureFile(
            URL(fileURLWithPath: "/tmp/Снимок 2026-07-18 12.00.00-\(captureID).source.png")
        ),
        "source ScreenshotApp capture is recognized"
    )
    try expect(
        CaptureFileClassifier.isManagedCaptureFile(
            URL(fileURLWithPath: "/tmp/Снимок 2026-07-18 12.00.00-\(captureID).project.json")
        ),
        "ScreenshotApp project is recognized"
    )
    try expect(
        !CaptureFileClassifier.isManagedCaptureFile(URL(fileURLWithPath: "/tmp/important.png")),
        "unrelated PNG files are never managed by ScreenshotApp"
    )
    try expect(
        !CaptureFileClassifier.isManagedCaptureFile(
            URL(fileURLWithPath: "/tmp/Снимок важное-\(captureID).png")
        ),
        "capture-like foreign file without the exact timestamp is not managed"
    )

    let fixtureFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenshotApp-classifier-\(UUID().uuidString)", isDirectory: true)
    let matchingDirectory = fixtureFolder.appendingPathComponent(fileName, isDirectory: true)
    let matchingSidecarDirectory = fixtureFolder
        .appendingPathComponent("Снимок 2026-07-18 12.00.00-\(captureID).project.json", isDirectory: true)
    let matchingRegularFile = fixtureFolder
        .appendingPathComponent("Снимок 2026-07-18 12.00.00-\(captureID).source.png")
    try FileManager.default.createDirectory(at: matchingDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: matchingSidecarDirectory, withIntermediateDirectories: true)
    try Data().write(to: matchingRegularFile)
    defer { try? FileManager.default.removeItem(at: fixtureFolder) }
    try expect(
        !CaptureFileClassifier.isRegularManagedCaptureFile(matchingDirectory),
        "a directory is never treated as a managed capture file"
    )
    try expect(
        CaptureFileClassifier.regularManagedCaptureFiles(
            in: [matchingDirectory, matchingSidecarDirectory, matchingRegularFile]
        ) == [matchingRegularFile],
        "the deletion plan contains only regular ScreenshotApp files"
    )
}

do {
    try checkModels()
    try checkHotKeyFormatting()
    try checkEditorState()
    try checkOverlapMatching()
    try checkAutomaticScrollFrameSelection()
    try checkCaptureCompletionPolicy()
    try checkCaptureProcessOutcome()
    try checkEditorCanvasLayout()
    try checkEditorZoomPolicy()
    try checkShelfSplitLayout()
    try checkScrollStitching()
    try checkAnnotationRendering()
    try checkShelfState()
    try checkScrollSession()
    try checkOCRTextOrdering()
    try checkShelfPlacementOnSecondaryDisplay()
    try checkCompactShelfMetrics()
    try checkShelfToggleGesturePolicy()
    try checkShelfWindowSizeStorage()
    try checkScreenshotTransferPayloads()
    try checkShelfCopyShortcuts()
    try checkCaptureTimestampFormatting()
    try checkHistoryRetentionPolicy()
    try checkManagedCaptureFiles()
    print("CoreChecks: OK")
} catch {
    fputs("CoreChecks: \(error)\n", stderr)
    exit(1)
}
