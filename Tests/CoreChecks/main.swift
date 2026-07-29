import AppKit
import CoreGraphics
import Foundation
import ImageIO
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

private func checkFrozenScreenCrop() throws {
    let pixelRect = FrozenScreenCrop.pixelRect(
        selection: CGRect(x: 100, y: 50, width: 200, height: 100),
        viewSize: CGSize(width: 1_000, height: 500),
        imagePixelSize: CGSize(width: 2_000, height: 1_000)
    )
    try expect(
        pixelRect == CGRect(x: 200, y: 100, width: 400, height: 200),
        "frozen screen selection maps from flipped points to Retina pixels"
    )

    let clamped = FrozenScreenCrop.pixelRect(
        selection: CGRect(x: 950, y: 480, width: 100, height: 100),
        viewSize: CGSize(width: 1_000, height: 500),
        imagePixelSize: CGSize(width: 2_000, height: 1_000)
    )
    try expect(
        clamped == CGRect(x: 1_900, y: 960, width: 100, height: 40),
        "frozen screen crop stays inside the captured image"
    )
}

private func requireValue<Value>(_ value: Value?, _ message: String) throws -> Value {
    guard let value else { throw CheckFailure.failed(message) }
    return value
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

private func checkActiveHotKeyPresentation() throws {
    let custom = HotKey(key: "S", keyCode: 1, modifiers: [.control, .option])
    try expect(
        ActiveHotKeyFormatter.symbolic(custom) == "⌥⌃S",
        "shelf formats the actually active hotkey"
    )
    try expect(
        ActiveHotKeyFormatter.readable(custom) == "Option (⌥) + Control (⌃) + S",
        "settings format the actually active hotkey"
    )
    try expect(ActiveHotKeyFormatter.symbolic(nil) == "—", "missing active hotkey is explicit on shelf")
    try expect(
        ActiveHotKeyFormatter.readable(nil) == "Не назначена",
        "missing active hotkey is explicit in settings"
    )
}

private func checkHotKeyStartupFallback() throws {
    let custom = HotKey(key: "S", keyCode: 1, modifiers: [.command, .option])
    try expect(
        HotKeyStartupPolicy.candidates(preferred: custom) == [custom, .defaultCapture],
        "startup falls back to the standard hotkey when a saved custom hotkey cannot register"
    )
    try expect(
        HotKeyStartupPolicy.candidates(preferred: .defaultCapture) == [.defaultCapture],
        "startup does not retry the same default hotkey"
    )
}

private enum SimulatedHotKeyRegistrationError: Error {
    case conflict
}

private func checkHotKeyRegistrationTransaction() throws {
    let previous = HotKey(key: "A", keyCode: 0, modifiers: [.command, .shift])
    let candidate = HotKey(key: "S", keyCode: 1, modifiers: [.command, .shift])
    var store = HotKeyRegistrationStore<String>()
    var unregisteredHandles: [String] = []

    store.replace(
        with: previous,
        register: { "previous-handle" },
        unregister: { unregisteredHandles.append($0) }
    )

    do {
        try store.replace(
            with: candidate,
            register: { throw SimulatedHotKeyRegistrationError.conflict },
            unregister: { unregisteredHandles.append($0) }
        )
        throw CheckFailure.failed("conflicting hotkey registration unexpectedly succeeded")
    } catch SimulatedHotKeyRegistrationError.conflict {
        // Expected: the previous working registration must remain active.
    }

    try expect(store.hotKey == previous, "hotkey conflict preserves the previous shortcut")
    try expect(store.handle == "previous-handle", "hotkey conflict preserves the previous Carbon handle")
    try expect(unregisteredHandles.isEmpty, "previous hotkey is not removed before a candidate succeeds")

    store.replace(
        with: candidate,
        register: { "candidate-handle" },
        unregister: { unregisteredHandles.append($0) }
    )
    try expect(store.hotKey == candidate, "successful replacement activates the candidate shortcut")
    try expect(store.handle == "candidate-handle", "successful replacement stores the candidate handle")
    try expect(unregisteredHandles == ["previous-handle"], "successful replacement removes the previous shortcut once")

    var repeatedRegistrationAttempts = 0
    store.replace(
        with: candidate,
        register: {
            repeatedRegistrationAttempts += 1
            return "duplicate-handle"
        },
        unregister: { unregisteredHandles.append($0) }
    )
    try expect(repeatedRegistrationAttempts == 0, "reapplying the same hotkey does not conflict with itself")
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

private func checkAnnotationDraftBuilder() throws {
    let style = AnnotationStyle(color: .red, lineWidth: 5)
    let start = NormalizedPoint(x: 0.25, y: 0.25)
    let end = NormalizedPoint(x: 0.75, y: 0.75)
    let rectangle = AnnotationDraftBuilder.make(
        kind: .rectangle,
        start: start,
        end: end,
        points: [],
        style: style
    )
    try expect(
        rectangle?.rect == NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
        "rectangle draft is visible with the current drag geometry"
    )

    let path = [start, NormalizedPoint(x: 0.5, y: 0.5), end]
    let pencil = AnnotationDraftBuilder.make(
        kind: .pencil,
        start: start,
        end: end,
        points: path,
        style: style
    )
    try expect(pencil?.points == path, "freehand draft follows the pointer before mouse-up")

    let clickOnly = AnnotationDraftBuilder.make(
        kind: .rectangle,
        start: start,
        end: start,
        points: [],
        style: style,
        minimumRectSize: 0.002
    )
    try expect(clickOnly == nil, "a click without a selected area does not create a rectangle")
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

    let blank = GrayImage(
        width: 8,
        height: 12,
        pixels: Array(repeating: 240, count: 96)
    )
    var sparsePixels = Array(repeating: UInt8(240), count: 96)
    sparsePixels[8 * 8 + 4] = 20
    let sparseFirst = GrayImage(width: 8, height: 12, pixels: sparsePixels)
    var shiftedSparsePixels = Array(repeating: UInt8(240), count: 96)
    shiftedSparsePixels[2 * 8 + 4] = 20
    let sparseSecond = GrayImage(width: 8, height: 12, pixels: shiftedSparsePixels)

    let blankMatch = try OverlapMatcher.bestVerticalMatch(previous: blank, next: blank)
    try expect(
        blankMatch.overlap == 0 && !blankMatch.meanDifference.isFinite,
        "a blank page has no trustworthy geometric overlap"
    )
    let sparseOverlap = try OverlapMatcher.bestVerticalOverlap(previous: sparseFirst, next: sparseSecond)
    try expect(
        sparseOverlap == 0,
        "a single mark on a mostly blank page cannot force a destructive scroll seam"
    )

    let blankDecision = try ScrollFrameClassifier.decision(
        previous: blank,
        next: blank,
        policy: ScrollFramePolicy(frameHeight: blank.height)
    )
    try expect(
        blankDecision == .unchanged,
        "identical blank viewports remain idle instead of producing an overlap warning"
    )
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

private func checkScrollFrameSettling() throws {
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
    var settler = ScrollFrameSettler()

    let idleOutcome = try settler.observe(
        accepted: first,
        observed: first,
        policy: policy,
        observedAt: 0
    )
    try expect(
        idleOutcome == .unchanged,
        "an idle viewport does not create a fake pending scroll frame"
    )
    let pendingOutcome = try settler.observe(
        accepted: first,
        observed: shifted,
        policy: policy,
        observedAt: 0
    )
    try expect(
        pendingOutcome == .pending(.append(overlap: 3)),
        "the first changed viewport is shown as pending instead of being captured mid-scroll"
    )
    let stillPendingOutcome = try settler.observe(
        accepted: first,
        observed: shifted,
        policy: policy,
        observedAt: 0.30
    )
    try expect(
        stillPendingOutcome == .pending(.append(overlap: 3)),
        "a viewport stopped for less than the settle interval is not captured"
    )
    let committedOutcome = try settler.observe(
        accepted: first,
        observed: shifted,
        policy: policy,
        observedAt: 0.36
    )
    try expect(
        committedOutcome == .commit(.append(overlap: 3)),
        "a viewport stopped continuously for one polling interval commits the pending frame"
    )
    let rejectedOutcome = try settler.observe(
        accepted: first,
        observed: unrelated,
        policy: policy,
        observedAt: 1.2
    )
    try expect(
        rejectedOutcome == .insufficientOverlap,
        "a viewport without overlap is rejected instead of being committed"
    )
}

private func checkScrollCapturePanelPlacement() throws {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1_200, height: 900)
    let panelSize = CGSize(width: 400, height: 100)
    let roomAbove = ScrollCapturePanelPlacement.frame(
        near: CGRect(x: 100, y: 400, width: 500, height: 300),
        panelSize: panelSize,
        visibleFrame: visibleFrame
    )
    try expect(
        roomAbove == CGRect(x: 150, y: 712, width: 400, height: 100),
        "the capture HUD stays directly above the selected area where the user is looking"
    )

    let onlyRoomBelow = ScrollCapturePanelPlacement.frame(
        near: CGRect(x: 100, y: 10, width: 500, height: 300),
        panelSize: panelSize,
        visibleFrame: visibleFrame
    )
    try expect(
        onlyRoomBelow == CGRect(x: 150, y: 322, width: 400, height: 100),
        "the capture HUD moves above a low selection instead of leaving the visible screen"
    )

    let fullHeightSelection = ScrollCapturePanelPlacement.frame(
        near: CGRect(x: 100, y: 40, width: 500, height: 820),
        panelSize: panelSize,
        visibleFrame: visibleFrame
    )
    try expect(
        fullHeightSelection == CGRect(x: 150, y: 748, width: 400, height: 100),
        "a full-height selection keeps the complete command HUD inside its top edge"
    )
}

private func checkScreenCoordinateTransform() throws {
    let mainScreenTop: CGFloat = 900
    let captureOnMain = CGRect(x: 100, y: 100, width: 500, height: 300)
    try expect(
        ScreenCoordinateTransform.appKitRect(
            fromCaptureRect: captureOnMain,
            mainScreenTop: mainScreenTop
        ) == CGRect(x: 100, y: 500, width: 500, height: 300),
        "capture coordinates map to the main AppKit screen"
    )

    let captureOnScreenAbove = CGRect(x: -300, y: -1_100, width: 600, height: 300)
    let appKitOnScreenAbove = ScreenCoordinateTransform.appKitRect(
        fromCaptureRect: captureOnScreenAbove,
        mainScreenTop: mainScreenTop
    )
    try expect(
        appKitOnScreenAbove == CGRect(x: -300, y: 1_700, width: 600, height: 300),
        "an external screen above the main display is not shifted by the desktop union height"
    )
    try expect(
        ScreenCoordinateTransform.captureRect(
            fromAppKitRect: appKitOnScreenAbove,
            mainScreenTop: mainScreenTop
        ) == captureOnScreenAbove,
        "AppKit and capture coordinates round-trip across multiple displays"
    )
}

private func checkScrollCaptureSourceGeometry() throws {
    let mainDisplay = ScrollCaptureSourceGeometry.resolve(
        captureRect: CGRect(x: 100, y: 120, width: 500, height: 300),
        displayRect: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
        pointPixelScale: 2
    )
    try expect(
        mainDisplay == ScrollCaptureSourceGeometry(
            sourceRect: CGRect(x: 100, y: 120, width: 500, height: 300),
            pixelWidth: 1_000,
            pixelHeight: 600
        ),
        "the filtered screenshot uses display-local coordinates and native pixel density"
    )

    let displayAboveMain = ScrollCaptureSourceGeometry.resolve(
        captureRect: CGRect(x: -250, y: -1_100, width: 500, height: 300),
        displayRect: CGRect(x: -300, y: -1_200, width: 600, height: 1_200),
        pointPixelScale: 1
    )
    try expect(
        displayAboveMain == ScrollCaptureSourceGeometry(
            sourceRect: CGRect(x: 50, y: 100, width: 500, height: 300),
            pixelWidth: 500,
            pixelHeight: 300
        ),
        "an elongated external display above the main screen keeps a local filtered capture rect"
    )

    try expect(
        ScrollCaptureSourceGeometry.resolve(
            captureRect: CGRect(x: 1_800, y: 100, width: 300, height: 300),
            displayRect: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            pointPixelScale: 2
        ) == nil,
        "a filtered capture never silently clips a selection that crosses display bounds"
    )
}

private func checkScrollCaptureStartPolicy() throws {
    try expect(
        ScrollCaptureStartPolicy.canStart(hasStarted: false, isProcessingFrame: false),
        "a selected scroll area can be explicitly started"
    )
    try expect(
        !ScrollCaptureStartPolicy.canStart(hasStarted: true, isProcessingFrame: false),
        "an active session cannot be started twice"
    )
    try expect(
        !ScrollCaptureStartPolicy.canStart(hasStarted: false, isProcessingFrame: true),
        "the start button waits for an in-flight first frame"
    )
}

private func checkScrollCaptureDirectionPolicy() throws {
    try expect(
        ScrollCaptureDirectionPolicy.accepts(.append(overlap: 300), lockedTo: nil),
        "the first accepted scroll frame establishes either direction"
    )
    try expect(
        ScrollCaptureDirectionPolicy.accepts(.append(overlap: 300), lockedTo: .down),
        "a downward capture continues accepting downward frames"
    )
    try expect(
        !ScrollCaptureDirectionPolicy.accepts(.prepend(overlap: 300), lockedTo: .down),
        "a backward correction cannot be inserted as a duplicate frame above a downward capture"
    )
    try expect(
        !ScrollCaptureDirectionPolicy.accepts(.append(overlap: 300), lockedTo: .up),
        "a backward correction cannot be appended below an upward capture"
    )
}

private func checkScrollCaptureFeedbackPolicy() throws {
    try expect(
        ScrollCaptureFeedbackPolicy.state(for: .pending(.append(overlap: 120))) == .aligning,
        "a moving viewport shows alignment progress before claiming the frame was saved"
    )
    try expect(
        ScrollCaptureFeedbackPolicy.state(for: ScrollFrameDecision.unchanged) == .ready,
        "an unchanged polling frame keeps the guide ready without pretending a frame was saved"
    )
    try expect(
        ScrollCaptureFeedbackPolicy.state(for: .append(overlap: 120)) == .acceptedDown,
        "a downward extension visibly confirms an accepted frame"
    )
    try expect(
        ScrollCaptureFeedbackPolicy.state(for: .prepend(overlap: 120)) == .acceptedUp,
        "an upward extension visibly confirms an accepted frame"
    )
    try expect(
        ScrollCaptureFeedbackPolicy.state(for: ScrollFrameDecision.insufficientOverlap) == .needsOverlap,
        "a jump without overlap shows a warning instead of a success flash"
    )
}

private func checkScrollCaptureCoveragePolicy() throws {
    let downward = ScrollCaptureCoveragePolicy.coverage(
        for: .append(overlap: 600),
        frameHeight: 900
    )
    try expect(
        downward == ScrollCaptureCoverage(
            alreadyCapturedEdge: .top,
            alreadyCapturedFraction: 2.0 / 3.0
        ),
        "downward scrolling shades the real overlap at the top of the selected area"
    )

    let upward = ScrollCaptureCoveragePolicy.coverage(
        for: .prepend(overlap: 450),
        frameHeight: 900
    )
    try expect(
        upward == ScrollCaptureCoverage(
            alreadyCapturedEdge: .bottom,
            alreadyCapturedFraction: 0.5
        ),
        "upward scrolling shades the real overlap at the bottom of the selected area"
    )

    let bounds = CGRect(x: 0, y: 0, width: 300, height: 900)

    try expect(
        ScrollCaptureOverlayLayout.layout(in: bounds, presentation: .selectionReady).markedRect == nil,
        "before a frame is accepted, the selected area remains unmarked and live"
    )

    let recoveryLayout = ScrollCaptureOverlayLayout.layout(
        in: bounds,
        presentation: .needsOverlap
    )
    try expect(
        recoveryLayout.markedRect == nil
            && recoveryLayout.boundaryY == nil,
        "an overlap warning does not falsely mark the unconfirmed viewport"
    )

    let capturedLayout = ScrollCaptureOverlayLayout.layout(
        in: bounds,
        presentation: .captured
    )
    try expect(
        capturedLayout.markedRect == bounds
            && capturedLayout.boundaryY == nil,
        "after a frame is accepted, its entire live viewport remains visibly marked as scanned"
    )

    let pendingLayout = ScrollCaptureOverlayLayout.layout(
        in: bounds,
        presentation: .pending(
            ScrollCaptureCoverage(
                alreadyCapturedEdge: .top,
                alreadyCapturedFraction: 2.0 / 3.0
            )
        )
    )
    try expect(
        pendingLayout.markedRect == CGRect(x: 0, y: 300, width: 300, height: 600)
            && pendingLayout.boundaryY == 300,
        "during downward scrolling, the scanned top content stays marked while new bottom content stays clear"
    )

    let upwardPendingLayout = ScrollCaptureOverlayLayout.layout(
        in: bounds,
        presentation: .pending(
            ScrollCaptureCoverage(
                alreadyCapturedEdge: .bottom,
                alreadyCapturedFraction: 0.5
            )
        )
    )
    try expect(
        upwardPendingLayout.markedRect == CGRect(x: 0, y: 0, width: 300, height: 450)
            && upwardPendingLayout.boundaryY == 450,
        "during upward scrolling, the scanned bottom content stays marked while new top content stays clear"
    )

    let zeroCoverageLayout = ScrollCaptureOverlayLayout.layout(
        in: bounds,
        presentation: .pending(
            ScrollCaptureCoverage(
                alreadyCapturedEdge: .top,
                alreadyCapturedFraction: 0
            )
        )
    )
    try expect(
        zeroCoverageLayout.markedRect == nil,
        "an overlap failure never falsely marks unseen live content as scanned"
    )

    let fullCoverageLayout = ScrollCaptureOverlayLayout.layout(
        in: bounds,
        presentation: .pending(
            ScrollCaptureCoverage(
                alreadyCapturedEdge: .bottom,
                alreadyCapturedFraction: 1
            )
        )
    )
    try expect(
        fullCoverageLayout.markedRect == bounds,
        "a fully overlapping live viewport remains fully marked"
    )
}

private func checkScrollCaptureTrail() throws {
    var trail = ScrollCaptureTrail()
    trail.append(frameHeight: 1_000, overlap: 600, captureHeight: 500)
    try expect(trail.appendHeight == 200, "append trail uses the new-content ratio")
    trail.prepend(frameHeight: 1_000, overlap: 800, captureHeight: 500)
    try expect(trail.prependHeight == 100, "prepend trail uses the new-content ratio")
    let clipped = trail.externalRect(
        captureRect: CGRect(x: 100, y: 100, width: 300, height: 500),
        screenRect: CGRect(x: 0, y: 0, width: 800, height: 700),
        direction: .down
    )
    try expect(clipped == CGRect(x: 100, y: 600, width: 300, height: 100), "trail clips to its screen")
    trail.undoLast()
    try expect(trail.prependHeight == 0 && trail.appendHeight == 200, "undo removes the last trail increment")
    trail.reset()
    try expect(trail.appendHeight == 0 && trail.prependHeight == 0, "reset clears the trail")
}

private func checkScrollCaptureCoverageRendering() throws {
    let bounds = CGRect(x: 0, y: 0, width: 300, height: 900)
    let view = ScrollCaptureCoverageView(frame: bounds)
    view.appearance = NSAppearance(named: .aqua)

    func renderedBitmap() throws -> NSBitmapImageRep {
        let bitmap = try requireValue(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width),
                pixelsHigh: Int(bounds.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            "scroll coverage view creates an RGBA render surface"
        )
        bitmap.size = bounds.size
        let context = try requireValue(
            NSGraphicsContext(bitmapImageRep: bitmap),
            "scroll coverage view creates an AppKit graphics context"
        )
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        view.displayIgnoringOpacity(view.bounds, in: context)
        context.flushGraphics()
        return bitmap
    }

    func alpha(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        let bitmapY = Int(bounds.height) - 1 - y
        return bitmap.colorAt(x: x, y: bitmapY)?.alphaComponent ?? 0
    }

    view.presentCapturedViewport()
    let captured = try renderedBitmap()
    try expect(
        (0.25..<0.45).contains(alpha(captured, x: 150, y: 100))
            && (0.25..<0.45).contains(alpha(captured, x: 150, y: 800)),
        "the real AppKit coverage view visibly marks the entire accepted viewport"
    )

    view.presentNeedsOverlap()
    let recovery = try renderedBitmap()
    try expect(
        alpha(recovery, x: 150, y: 100) < 0.01
            && alpha(recovery, x: 150, y: 800) < 0.01,
        "the real AppKit coverage view does not mark an unconfirmed viewport during recovery"
    )

    view.present(
        coverage: ScrollCaptureCoverage(
            alreadyCapturedEdge: .top,
            alreadyCapturedFraction: 2.0 / 3.0
        )
    )
    let pendingDown = try renderedBitmap()
    let pendingDownLowAlpha = alpha(pendingDown, x: 150, y: 150)
    let pendingDownHighAlpha = alpha(pendingDown, x: 150, y: 750)
    try expect(
        pendingDownHighAlpha > 0.25
            && pendingDownLowAlpha < 0.01,
        "during downward scrolling, the real AppKit view marks old content and leaves new content clear "
            + "(low alpha: \(pendingDownLowAlpha), high alpha: \(pendingDownHighAlpha))"
    )

    view.present(
        coverage: ScrollCaptureCoverage(
            alreadyCapturedEdge: .bottom,
            alreadyCapturedFraction: 0.5
        )
    )
    let pendingUp = try renderedBitmap()
    let pendingUpLowAlpha = alpha(pendingUp, x: 150, y: 150)
    let pendingUpHighAlpha = alpha(pendingUp, x: 150, y: 750)
    try expect(
        pendingUpLowAlpha > 0.25
            && pendingUpHighAlpha < 0.01,
        "during upward scrolling, the real AppKit view marks old content and leaves new content clear "
            + "(low alpha: \(pendingUpLowAlpha), high alpha: \(pendingUpHighAlpha))"
    )

    var externalTrail = ScrollCaptureTrail()
    externalTrail.append(frameHeight: 1_000, overlap: 500, captureHeight: 300)
    view.configure(
        captureRect: CGRect(x: 50, y: 300, width: 200, height: 300),
        screenRect: bounds,
        trail: externalTrail
    )
    view.presentCapturedViewport()
    let externalTrailBitmap = try renderedBitmap()
    try expect(
        alpha(externalTrailBitmap, x: 150, y: 650) > 0.15
            && alpha(externalTrailBitmap, x: 150, y: 800) < 0.01
            && alpha(externalTrailBitmap, x: 20, y: 650) < 0.01,
        "the real AppKit view renders the accepted trail outside the selected rectangle only"
    )
}

private func checkCaptureCompletionPolicy() throws {
    try expect(CaptureCompletionPolicy.standard.opensEditor, "a finished screenshot opens the editor")
    try expect(CaptureCompletionPolicy.standard.revealsShelf, "a finished screenshot remains available on the shelf")
}

private func checkAreaCaptureRecoveryPolicy() throws {
    try expect(
        AreaCaptureRecoveryPolicy.action(hasActiveAreaCapture: false) == .start,
        "an idle hotkey starts a new area capture"
    )
    try expect(
        AreaCaptureRecoveryPolicy.action(hasActiveAreaCapture: true) == .cancelAndRestart,
        "a repeated hotkey recovers a stuck area capture instead of being ignored"
    )
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

private func checkImageFileMetadata() throws {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenshotApp-metadata-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: fixtureURL) }

    guard let context = CGContext(
        data: nil,
        width: 13,
        height: 7,
        bitsPerComponent: 8,
        bytesPerRow: 13 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let image = context.makeImage(),
       let destination = CGImageDestinationCreateWithURL(
           fixtureURL as CFURL,
           UTType.png.identifier as CFString,
           1,
           nil
       ) else {
        throw CheckFailure.failed("image metadata fixture can be created")
    }
    CGImageDestinationAddImage(destination, image, nil)
    try expect(CGImageDestinationFinalize(destination), "image metadata fixture can be written")

    try expect(
        ImageFileMetadata.dimensions(at: fixtureURL) == PixelDimensions(width: 13, height: 7),
        "PNG dimensions are read without rendering the full image"
    )
    try expect(
        ImageFileMetadata.dimensions(at: fixtureURL.appendingPathExtension("missing")) == nil,
        "missing images do not produce fake dimensions"
    )
}

private func checkCaptureActivityState() throws {
    let firstCaptureID = UUID()
    let secondCaptureID = UUID()
    let storageChangeID = UUID()
    var state = CaptureActivityState()

    try expect(state.canStartCapture, "capture starts while the app is idle")
    try expect(state.canChangeStorage, "storage can change while the app is idle")
    try expect(
        state.beginCapture(id: firstCaptureID),
        "the first interactive capture starts"
    )
    try expect(!state.beginCapture(id: secondCaptureID), "a second selector cannot overlap the first")
    try expect(!state.canChangeStorage, "storage cannot change during interactive capture")
    try expect(
        state.finishCaptureAndBeginImport(id: firstCaptureID),
        "a finished interactive capture becomes a background import"
    )
    try expect(state.canStartCapture, "a new hotkey is accepted while the previous image imports")
    try expect(!state.canChangeStorage, "storage stays fixed while an import is pending")
    try expect(state.beginCapture(id: secondCaptureID), "the second capture starts during the first import")
    try expect(
        state.finishImport(id: firstCaptureID),
        "the first import can finish while the second selector is active"
    )
    try expect(state.isCaptureActive, "finishing an old import never clears a newer active capture")
    try expect(!state.canStartCapture, "the active second selector still blocks a third capture")
    try expect(state.cancelCapture(id: secondCaptureID), "the matching capture can be cancelled")
    try expect(state.canChangeStorage, "storage unlocks after capture and imports finish")
    try expect(
        state.beginStorageChange(id: storageChangeID),
        "the storage picker owns the foreground operation"
    )
    try expect(!state.canStartCapture, "the hotkey waits while the storage picker is open")
    try expect(
        state.finishStorageChange(id: storageChangeID),
        "closing the storage picker returns the app to idle"
    )
}

private func checkCaptureResultOrder() throws {
    try expect(
        CaptureResultOrder.sequenceToPresent(pending: [1, 2], latestPresented: 0) == 2,
        "when imports finish together only the newest capture is presented"
    )
    try expect(
        CaptureResultOrder.sequenceToPresent(pending: [1], latestPresented: 2) == nil,
        "a late older import never replaces a newer presented capture"
    )
    try expect(
        CaptureResultOrder.sequenceToPresent(pending: [4, 3], latestPresented: 2) == 4,
        "presentation order follows capture order instead of import completion order"
    )
}

private func checkImageLoadRequestState() throws {
    let request = ImageLoadRequestKey(path: "/tmp/long.png", maximumPixelSize: 4_096, revision: 1)
    let replacement = ImageLoadRequestKey(path: "/tmp/new.png", maximumPixelSize: 320, revision: 1)
    var state = ImageLoadRequestState()

    let firstToken = try requireValue(state.begin(request), "first image request starts")
    let retryToken = try requireValue(state.begin(request), "an in-flight request can be superseded")
    try expect(firstToken != retryToken, "a retry receives a new generation")
    try expect(
        !state.finish(firstToken, request: request),
        "a stale decode cannot replace a newer request"
    )
    try expect(state.fail(retryToken), "a failed current decode clears the active request")
    let afterFailure = try requireValue(state.begin(request), "the same request retries after failure")
    try expect(state.finish(afterFailure, request: request), "the successful retry is committed")
    try expect(state.begin(request) == nil, "an already loaded request is not decoded again")
    let replacementToken = try requireValue(state.begin(replacement), "a changed request starts")
    try expect(state.cancel(replacementToken), "cancelling the current request clears it")
    try expect(state.begin(replacement) != nil, "the same request retries after cancellation")
}

private func checkShelfPreviewDecodePolicy() throws {
    let viewport = CanvasSize(width: 380, height: 400)
    let longImage = PixelDimensions(width: 1_440, height: 100_000)
    let initial = ShelfPreviewDecodePolicy.plan(
        image: longImage,
        viewport: viewport,
        zoomScale: 1,
        backingScale: 2
    )
    let zoomed = ShelfPreviewDecodePolicy.plan(
        image: longImage,
        viewport: viewport,
        zoomScale: 64,
        backingScale: 2
    )
    let nearbyInitialZoom = ShelfPreviewDecodePolicy.plan(
        image: longImage,
        viewport: viewport,
        zoomScale: 1.1,
        backingScale: 2
    )

    try expect(
        zoomed.maximumPixelSize > initial.maximumPixelSize,
        "pinch zoom progressively requests a sharper long screenshot"
    )
    try expect(
        nearbyInitialZoom.maximumPixelSize == initial.maximumPixelSize,
        "small zoom changes inside one resolution step do not trigger another decode"
    )
    try expect(
        zoomed.estimatedDimensions.width >= 450,
        "an extreme vertical screenshot keeps a readable short edge at maximum zoom"
    )
    try expect(
        zoomed.estimatedPixelCount <= ShelfPreviewDecodePolicy.maximumDecodedPixels,
        "an extreme vertical screenshot stays inside the decoded-pixel budget"
    )

    let square = ShelfPreviewDecodePolicy.plan(
        image: PixelDimensions(width: 20_000, height: 20_000),
        viewport: viewport,
        zoomScale: 20,
        backingScale: 2
    )
    try expect(
        square.estimatedPixelCount <= ShelfPreviewDecodePolicy.maximumDecodedPixels,
        "a square screenshot also stays inside the decoded-pixel budget"
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
    let outputPixels = try ScrollStitcher.grayImage(from: output).pixels
    try expect(
        outputPixels == [
            0, 0, 10, 10, 20, 20, 30, 30, 40, 40, 50, 50,
        ],
        "stitching preserves the first frame and appends only newly revealed rows"
    )

    let stickyFirst = try makeGrayImage(
        width: 2,
        height: 6,
        pixels: [240, 240, 10, 10, 20, 20, 30, 30, 40, 40, 50, 50]
    )
    let stickySecond = try makeGrayImage(
        width: 2,
        height: 6,
        pixels: [240, 240, 30, 30, 40, 40, 50, 50, 60, 60, 70, 70]
    )
    let stickyFirstGray = try ScrollStitcher.grayImage(from: stickyFirst)
    let stickySecondGray = try ScrollStitcher.grayImage(from: stickySecond)
    let stickyMatch = try OverlapMatcher.bestVerticalMatch(previous: stickyFirstGray, next: stickySecondGray)
    try expect(stickyMatch.overlap == 4, "a fixed top bar is excluded from scroll overlap matching")
    let stickyOutput = try ScrollStitcher.stitch([stickyFirst, stickySecond])
    try expect(stickyOutput.height == 8, "a fixed top bar is kept once instead of creating a crooked seam")
    let stickyOutputPixels = try ScrollStitcher.grayImage(from: stickyOutput).pixels
    try expect(
        stickyOutputPixels == [
            240, 240, 10, 10, 20, 20, 30, 30, 40, 40, 50, 50, 60, 60, 70, 70,
        ],
        "a fixed top bar is not repeated inside the stitched page"
    )

    let hoverPreservedFirst = try makeGrayImage(
        width: 2,
        height: 6,
        pixels: [220, 220, 210, 210, 200, 200, 190, 190, 180, 180, 170, 170]
    )
    let filteredBaseline = try makeGrayImage(
        width: 2,
        height: 6,
        pixels: [0, 0, 10, 10, 20, 20, 30, 30, 40, 40, 50, 50]
    )
    let filteredAfterScroll = try makeGrayImage(
        width: 2,
        height: 6,
        pixels: [30, 30, 40, 40, 50, 50, 60, 60, 70, 70, 80, 80]
    )
    let filteredDecision = try ScrollFrameClassifier.decision(
        previous: try ScrollStitcher.grayImage(from: filteredBaseline),
        next: try ScrollStitcher.grayImage(from: filteredAfterScroll),
        policy: ScrollFramePolicy(
            minimumNewRows: 2,
            minimumOverlapRows: 2,
            maximumMeanDifference: 20
        )
    )
    try expect(
        filteredDecision == .append(overlap: 3),
        "classification uses the stable filtered baseline instead of the hover-preserved output"
    )
    let hoverPreservedOutput = try ScrollStitcher.stitch(
        [hoverPreservedFirst, filteredAfterScroll],
        overlaps: [3]
    )
    try expect(
        hoverPreservedOutput.height == 9,
        "the first seam reuses the filtered baseline overlap while preserving the hover frame"
    )
    let hoverPreservedPixels = try ScrollStitcher.grayImage(from: hoverPreservedOutput).pixels
    try expect(
        hoverPreservedPixels == [
            220, 220, 210, 210, 200, 200, 190, 190, 180, 180, 170, 170,
            60, 60, 70, 70, 80, 80,
        ],
        "the output keeps the exact selected first frame and appends only newly revealed rows"
    )

    let filteredAboveScroll = try makeGrayImage(
        width: 2,
        height: 6,
        pixels: [30, 30, 40, 40, 50, 50, 60, 60, 70, 70, 80, 80]
    )
    let hoverPreservedUpOutput = try ScrollStitcher.stitch(
        [filteredAboveScroll, hoverPreservedFirst],
        seams: [.prepend(overlap: 3)]
    )
    let hoverPreservedUpPixels = try ScrollStitcher.grayImage(from: hoverPreservedUpOutput).pixels
    try expect(
        hoverPreservedUpPixels == [
            30, 30, 40, 40, 50, 50,
            220, 220, 210, 210, 200, 200, 190, 190, 180, 180, 170, 170,
        ],
        "an upward first seam prepends only new filtered rows and keeps the full hover frame"
    )
}

private func checkScrollFrameNormalization() throws {
    let lowResolution = try makeGrayImage(
        width: 2,
        height: 2,
        pixels: [0, 0, 100, 100]
    )
    let normalized = try ScrollFrameNormalizer.normalized(
        lowResolution,
        width: 4,
        height: 4
    )
    try expect(
        normalized.width == 4 && normalized.height == 4,
        "scroll frames captured at a different Retina scale are normalized before stitching"
    )
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

    let hoverFirst = try makeGrayImage(
        width: 2,
        height: 4,
        pixels: [220, 220, 210, 210, 200, 200, 190, 190]
    )
    var hoverSession = ScrollCaptureSession(frames: [hoverFirst])
    hoverSession.add(below, direction: .down, overlap: 2)
    try expect(
        hoverSession.frames.first === hoverFirst,
        "scroll session keeps the hover-preserved first output frame"
    )
    try expect(
        hoverSession.seamOverlaps == [2],
        "scroll session records the classifier-approved seam"
    )
    let hoverOutput = try hoverSession.finish()
    try expect(
        hoverOutput.height == 6,
        "scroll session finishes with its recorded filtered-baseline seam"
    )

    var hoverUpSession = ScrollCaptureSession(frames: [hoverFirst])
    hoverUpSession.add(above, direction: .up, overlap: 2)
    try expect(
        hoverUpSession.stitchSeams == [.prepend(overlap: 2)],
        "upward capture records a prepend seam instead of a normal ordered overlap"
    )
    let hoverUpOutput = try hoverUpSession.finish()
    let hoverUpPixels = try ScrollStitcher.grayImage(from: hoverUpOutput).pixels
    try expect(
        hoverUpPixels == [
            0, 0, 10, 10,
            220, 220, 210, 210, 200, 200, 190, 190,
        ],
        "upward session prepends only unseen rows before the full hover-preserved frame"
    )
}

private func checkScrollCaptureFinishPolicy() throws {
    try expect(
        ScrollCaptureFinishPolicy.canFinish(isCapturing: true, isFinalizing: false),
        "scroll capture can finish while an automatic frame is being captured"
    )
    try expect(
        !ScrollCaptureFinishPolicy.canFinish(isCapturing: false, isFinalizing: false),
        "scroll capture cannot finish after it has stopped"
    )
    try expect(
        !ScrollCaptureFinishPolicy.canFinish(isCapturing: true, isFinalizing: true),
        "scroll capture cannot start a second stitch"
    )
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
            isLiveResize: false,
            isFullScreen: false
        ),
        "system layout changes never overwrite the preferred expanded size"
    )
    try expect(
        ShelfWindowResizePolicy.shouldPersist(
            isExpanded: true,
            isApplyingPresentation: false,
            isLiveResize: true,
            isFullScreen: false
        ),
        "a user live-resize persists the preferred expanded size"
    )
    try expect(
        !ShelfWindowResizePolicy.shouldPersist(
            isExpanded: true,
            isApplyingPresentation: false,
            isLiveResize: true,
            isFullScreen: true
        ),
        "full-screen transitions never overwrite the preferred expanded size"
    )
}

private func checkShelfWindowChromePolicy() throws {
    try expect(
        ShelfWindowChromePolicy.showsCustomControls(in: .expanded),
        "expanded shelf shows its always-visible colored window controls"
    )
    try expect(
        !ShelfWindowChromePolicy.showsCustomControls(in: .collapsed),
        "collapsed shelf keeps its compact glass shape"
    )
    try expect(
        !ShelfWindowChromePolicy.showsCustomControls(in: .hiddenUntilNextCapture),
        "hidden shelf has no active window controls"
    )
}

private func checkApplicationInstallation() throws {
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    let userApplications = home.appendingPathComponent("Applications", isDirectory: true)
    let destination = ApplicationInstallPolicy.destinationURL(
        homeDirectory: home,
        appBundleName: "Богдан Скриншот.app"
    )
    try expect(
        destination == userApplications.appendingPathComponent("Богдан Скриншот.app", isDirectory: true),
        "installer targets the user's Applications folder without administrator privileges"
    )
    try expect(
        ApplicationInstallPolicy.isInstalled(
            bundleURL: destination,
            homeDirectory: home
        ),
        "an app in the user's Applications folder is installed"
    )
    try expect(
        ApplicationInstallPolicy.isInstalled(
            bundleURL: URL(fileURLWithPath: "/Applications/Богдан Скриншот.app", isDirectory: true),
            homeDirectory: home
        ),
        "an app in the system Applications folder is installed"
    )
    let downloaded = home
        .appendingPathComponent("Downloads", isDirectory: true)
        .appendingPathComponent("Богдан Скриншот.app", isDirectory: true)
    try expect(
        !ApplicationInstallPolicy.isInstalled(bundleURL: downloaded, homeDirectory: home),
        "a downloaded app is offered installation instead of running in place"
    )
    try expect(
        ApplicationInstallPolicy.cleanupCandidate(
            sourceBundleURL: downloaded,
            installedBundleURL: destination,
            userApprovedCleanup: false
        ) == nil,
        "the downloaded copy is never removed without explicit consent"
    )
    try expect(
        ApplicationInstallPolicy.cleanupCandidate(
            sourceBundleURL: downloaded,
            installedBundleURL: destination,
            userApprovedCleanup: true
        ) == downloaded,
        "the downloaded copy is selected for Trash after explicit consent"
    )
    try expect(
        ApplicationInstallPolicy.cleanupCandidate(
            sourceBundleURL: destination,
            installedBundleURL: destination,
            userApprovedCleanup: true
        ) == nil,
        "the installed copy can never delete itself"
    )

    let fixtureRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenshotApp-install-\(UUID().uuidString)", isDirectory: true)
    let source = fixtureRoot.appendingPathComponent("Source.app", isDirectory: true)
    let sourceContents = source.appendingPathComponent("Contents", isDirectory: true)
    let target = fixtureRoot.appendingPathComponent("Applications/Target.app", isDirectory: true)
    let targetContents = target.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceContents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: targetContents, withIntermediateDirectories: true)
    try Data("new".utf8).write(to: sourceContents.appendingPathComponent("payload"))
    try Data("old".utf8).write(to: targetContents.appendingPathComponent("payload"))
    defer { try? FileManager.default.removeItem(at: fixtureRoot) }

    try ApplicationBundleInstaller.install(sourceBundleURL: source, destinationBundleURL: target)
    let installedPayload = try String(
        contentsOf: targetContents.appendingPathComponent("payload"),
        encoding: .utf8
    )
    try expect(
        installedPayload == "new",
        "installer replaces an older installed application with the downloaded version"
    )
    try expect(FileManager.default.fileExists(atPath: source.path), "installer preserves source until cleanup consent")
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

private func checkCaptureFileNames() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 21,
        hour: 10,
        minute: 32,
        second: 48
    ))!
    try expect(
        CaptureFileName.baseStem(
            for: date,
            applicationName: "Telegram",
            calendar: calendar,
            locale: Locale(identifier: "ru_RU")
        ) == "21 июля, 10.32 - Telegram",
        "new capture filename contains date, time, and application only"
    )
    try expect(
        CaptureFileName.baseStem(
            for: date,
            applicationName: nil,
            calendar: calendar,
            locale: Locale(identifier: "ru_RU")
        ) == "21 июля, 10.32",
        "capture filename omits an unavailable application cleanly"
    )
    try expect(
        CaptureFileName.baseStem(
            for: date,
            applicationName: "  Safari / Browser:*?<>|\"\n",
            calendar: calendar,
            locale: Locale(identifier: "ru_RU")
        ) == "21 июля, 10.32 - Safari Browser",
        "application names are safe and compact in local filenames"
    )
    try expect(
        CaptureFileName.availableStem(
            baseStem: "21 июля, 10.32 - Telegram",
            occupiedStems: [
                "21 июля, 10.32 - Telegram",
                "21 июля, 10.32 - Telegram (2)",
            ]
        ) == "21 июля, 10.32 - Telegram (3)",
        "readable filename collisions receive a visible numeric suffix"
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

    let unlimited = HistoryIndex.pruned(
        items: fixtures,
        automaticCleanupEnabled: false,
        maximumCount: 3,
        maximumAgeDays: 1,
        now: now.addingTimeInterval(10 * 86_400)
    )
    try expect(unlimited.count == fixtures.count, "disabled automatic cleanup retains every capture")
    try expect(unlimited.first?.id == fixtures.last?.id, "unlimited history remains newest-first")
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
    let readableStem = "21 июля, 10.32 - Telegram"
    try expect(
        CaptureFileClassifier.isRenderedCapture(
            URL(fileURLWithPath: "/tmp/\(readableStem).png")
        ),
        "new readable rendered capture is recognized"
    )
    try expect(
        CaptureFileClassifier.isManagedCaptureFile(
            URL(fileURLWithPath: "/tmp/\(readableStem).source.png")
        ),
        "new readable source capture is recognized"
    )
    try expect(
        CaptureFileClassifier.isManagedCaptureFile(
            URL(fileURLWithPath: "/tmp/\(readableStem).project.json")
        ),
        "new readable project is recognized"
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

private func checkAutomaticUpdateDefaultsMigration() throws {
    let suiteName = "AutomaticUpdateDefaultsMigrationTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw CheckFailure.failed("cannot create isolated update defaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    try expect(
        AutomaticUpdateDefaultsMigration.shouldEnableAutomaticUpdates(in: defaults),
        "automatic updates are enabled for an existing installation exactly once"
    )
    try expect(
        !AutomaticUpdateDefaultsMigration.shouldEnableAutomaticUpdates(in: defaults),
        "a user's later update preference is preserved after migration"
    )
}

private func checkLaunchAtLoginPolicy() throws {
    try expect(
        LaunchAtLoginPolicy.action(desiredEnabled: true, status: .notRegistered) == .register,
        "enabling an unregistered login item registers the main app"
    )
    try expect(
        LaunchAtLoginPolicy.action(desiredEnabled: true, status: .enabled) == .none,
        "an enabled login item is not registered twice"
    )
    try expect(
        LaunchAtLoginPolicy.action(desiredEnabled: true, status: .requiresApproval) == .none,
        "a denied login item waits for explicit approval instead of retrying registration"
    )
    try expect(
        LaunchAtLoginPolicy.action(desiredEnabled: true, status: .notFound) == .register,
        "a missing main-app registration is repaired instead of becoming a permanent no-op"
    )
    try expect(
        LaunchAtLoginPolicy.action(desiredEnabled: false, status: .enabled) == .unregister,
        "disabling an enabled login item unregisters the main app"
    )
    try expect(
        LaunchAtLoginPolicy.action(desiredEnabled: false, status: .notRegistered) == .none,
        "an unregistered login item is not unregistered twice"
    )
    try expect(
        LaunchAtLoginPolicy.isEnabled(status: .enabled),
        "the settings toggle is on only for an actually enabled login item"
    )
    try expect(
        !LaunchAtLoginPolicy.isEnabled(status: .requiresApproval),
        "a login item awaiting approval is not shown as enabled"
    )
    try expect(
        LaunchAtLoginPolicy.statusMessage(status: .requiresApproval)
            == "Разрешите автозапуск в системных настройках macOS.",
        "approval-required state has an actionable Russian explanation"
    )
    try expect(
        LaunchAtLoginPolicy.statusMessage(status: .notFound)
            == "macOS не нашла приложение среди объектов входа.",
        "missing login item has an actionable Russian explanation"
    )
    try expect(
        LaunchAtLoginPolicy.diagnosticValue(status: .enabled) == "enabled",
        "launch-at-login diagnostics expose the actual normalized status"
    )

    let suiteName = "LaunchAtLoginDefaultsMigrationTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw CheckFailure.failed("cannot create isolated launch-at-login defaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    try expect(
        LaunchAtLoginDefaultsMigration.shouldEnableLaunchAtLogin(in: defaults),
        "launch at login is enabled for an existing installation"
    )
    try expect(
        LaunchAtLoginDefaultsMigration.shouldEnableLaunchAtLogin(in: defaults),
        "a failed first registration remains retryable"
    )
    LaunchAtLoginDefaultsMigration.markLaunchAtLoginHandled(in: defaults)
    try expect(
        !LaunchAtLoginDefaultsMigration.shouldEnableLaunchAtLogin(in: defaults),
        "a user's later login-item preference is preserved after migration"
    )
}

do {
    try checkFrozenScreenCrop()
    try checkModels()
    try checkHotKeyFormatting()
    try checkActiveHotKeyPresentation()
    try checkHotKeyStartupFallback()
    try checkHotKeyRegistrationTransaction()
    try checkEditorState()
    try checkAnnotationDraftBuilder()
    try checkOverlapMatching()
    try checkAutomaticScrollFrameSelection()
    try checkScrollFrameSettling()
    try checkScrollCapturePanelPlacement()
    try checkScreenCoordinateTransform()
    try checkScrollCaptureSourceGeometry()
    try checkScrollCaptureStartPolicy()
    try checkScrollCaptureDirectionPolicy()
    try checkScrollCaptureFeedbackPolicy()
    try checkScrollCaptureCoveragePolicy()
    try checkScrollCaptureTrail()
    try checkScrollCaptureCoverageRendering()
    try checkCaptureCompletionPolicy()
    try checkAreaCaptureRecoveryPolicy()
    try checkCaptureProcessOutcome()
    try checkImageFileMetadata()
    try checkCaptureActivityState()
    try checkCaptureResultOrder()
    try checkImageLoadRequestState()
    try checkShelfPreviewDecodePolicy()
    try checkEditorCanvasLayout()
    try checkEditorZoomPolicy()
    try checkShelfSplitLayout()
    try checkScrollStitching()
    try checkAnnotationRendering()
    try checkShelfState()
    try checkScrollSession()
    try checkScrollCaptureFinishPolicy()
    try checkScrollFrameNormalization()
    try checkOCRTextOrdering()
    try checkShelfPlacementOnSecondaryDisplay()
    try checkCompactShelfMetrics()
    try checkShelfToggleGesturePolicy()
    try checkShelfWindowSizeStorage()
    try checkShelfWindowChromePolicy()
    try checkApplicationInstallation()
    try checkScreenshotTransferPayloads()
    try checkShelfCopyShortcuts()
    try checkCaptureTimestampFormatting()
    try checkCaptureFileNames()
    try checkHistoryRetentionPolicy()
    try checkManagedCaptureFiles()
    try checkAutomaticUpdateDefaultsMigration()
    try checkLaunchAtLoginPolicy()
    print("CoreChecks: OK")
} catch {
    fputs("CoreChecks: \(error)\n", stderr)
    exit(1)
}
