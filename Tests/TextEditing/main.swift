import AppKit
import Foundation
import ScreenshotCore
@testable import ScreenshotApp

@main
struct TextEditingChecks {
    @MainActor
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotApp-text-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaultsName = "TextEditingChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.captureFolder = folder
        let model = AppModel(preferences: preferences)
        let sourceURL = folder.appendingPathComponent("source.png")
        let imageURL = folder.appendingPathComponent("capture.png")
        let image = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 400,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        image.bitmapData!.initialize(repeating: 255, count: image.bytesPerRow * image.pixelsHigh)
        let png = image.representation(using: .png, properties: [:])!
        try png.write(to: sourceURL)
        try png.write(to: imageURL)
        let projectURL = folder.appendingPathComponent("project.json")
        let document = EditorDocument(
            imageFileName: sourceURL.lastPathComponent,
            canvasSize: CanvasSize(width: 640, height: 400), annotations: []
        )
        try JSONEncoder().encode(document).write(to: projectURL)
        let item = CaptureItem(
            id: UUID(), createdAt: Date(), imageURL: imageURL,
            projectURL: projectURL,
            pixelWidth: 640, pixelHeight: 400
        )
        let session = EditorSession(item: item, model: model)!
        session.tool = .text
        session.textValue = "Первая надпись"
        let point = NormalizedPoint(x: 0.1, y: 0.2)
        session.add(start: point, end: point, points: [point])
        let firstID = session.state.document.annotations[0].id
        let previewBeforeEditing = session.preview.tiffRepresentation
        session.textValue = "Свой"
        session.textValue = "Свой текст из буфера"
        precondition(session.state.document.annotations.count == 1, "Editing must not add a layer")
        precondition(session.state.document.annotations[0].id == firstID, "Editing must preserve the layer ID")
        precondition(session.state.document.annotations[0].text == "Свой текст из буфера", "Changing the text field must update the placed label")
        precondition(session.preview.tiffRepresentation != previewBeforeEditing, "The canvas must render the edited text immediately")
        session.undo()
        precondition(session.state.document.annotations[0].text == "Первая надпись", "Continuous text editing must undo in one step")
        session.redo()
        precondition(session.state.document.annotations[0].text == "Свой текст из буфера", "Redo must restore edited text")

        let secondPoint = NormalizedPoint(x: 0.55, y: 0.7)
        session.add(start: secondPoint, end: secondPoint, points: [secondPoint])
        session.textValue = "Вторая надпись"
        session.finishTextEditing()
        session.selectText(firstID)
        precondition(session.textValue == "Свой текст из буфера", "Selecting an existing label must load its text into the field")
        session.textValue = "Изменена первая"
        precondition(session.state.document.annotations.count == 2, "Selecting text must not add a duplicate label")
        precondition(session.state.document.annotations[1].text == "Вторая надпись", "Editing must leave other labels unchanged")
        session.finishTextEditing()
        session.textValue = "Еще одна правка"
        session.undo()
        precondition(session.state.document.annotations[0].text == "Изменена первая", "A new editing session must have its own undo step")

        session.selectText(firstID)
        session.textValue = ""
        let emptyBounds = AnnotationTextLayout.bounds(
            for: session.state.document.annotations[0], canvasSize: document.canvasSize
        )!
        precondition(emptyBounds.width > 0 && emptyBounds.height > 0, "An empty label must remain selectable")
        session.textValue = "Сохраненный текст"
        precondition(session.save(), "Saving edited text must succeed")
        let reopened = EditorSession(item: item, model: model)!
        precondition(reopened.state.document == session.state.document, "Edited text and layer IDs must survive reopening")
        reopened.selectText(firstID)
        precondition(!reopened.state.canUndo, "Selecting saved text must not add an undo step")
        reopened.textValue = "Правка после открытия"
        precondition(reopened.state.document.annotations[0].text == "Правка после открытия", "Saved labels must remain editable")
        reopened.tool = .rectangle
        reopened.textValue = "Текст для нового слоя"
        precondition(reopened.state.document.annotations[0].text == "Правка после открытия", "Changing tools must finish editing the selected label")
        var nonTextState = EditorState(document: .empty)
        let line = Annotation.line(from: .zero, to: point, style: .init(color: .red))
        nonTextState.add(line)
        nonTextState.updateSelectedText("Не текст")
        precondition(nonTextState.document.annotations == [line], "Text editing must ignore non-text layers")
        precondition(AnnotationTextLayout.bounds(for: line, canvasSize: document.canvasSize) == nil)
        if let path = ProcessInfo.processInfo.environment["SCREENSHOT_TEXT_FIXTURE_DIR"] {
            let fixture = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
            let stem = CaptureFileName.baseStem(for: Date(), applicationName: "Проверка текста")
            var fixtureDocument = session.state.document
            fixtureDocument.imageFileName = "\(stem).source.png"
            try png.write(to: fixture.appendingPathComponent(fixtureDocument.imageFileName))
            try Data(contentsOf: imageURL).write(to: fixture.appendingPathComponent("\(stem).png"))
            try JSONEncoder().encode(fixtureDocument).write(
                to: fixture.appendingPathComponent("\(stem).project.json")
            )
            let fixtureHistory = HistoryStore(
                folderURL: fixture, maximumCount: 20, maximumAgeDays: 30,
                automaticCleanupEnabled: false
            )
            try fixtureHistory.reload()
            precondition(fixtureHistory.items.count == 1, "The UI fixture must load as one managed screenshot")
        }
        print("TextEditingChecks: OK")
    }
}
