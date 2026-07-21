import AppKit
import ScreenshotCore
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case arrow
    case line
    case rectangle
    case ellipse
    case pencil
    case highlighter
    case text
    case counter
    case blur
    case pixelate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow: "Стрелка"
        case .line: "Линия"
        case .rectangle: "Рамка"
        case .ellipse: "Овал"
        case .pencil: "Карандаш"
        case .highlighter: "Маркер"
        case .text: "Текст"
        case .counter: "Шаг"
        case .blur: "Блюр"
        case .pixelate: "Пиксели"
        }
    }

    var icon: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .pencil: "pencil.tip"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .counter: "1.circle"
        case .blur: "drop.halffull"
        case .pixelate: "square.grid.3x3.fill"
        }
    }

    var annotationKind: AnnotationKind { AnnotationKind(rawValue: rawValue)! }
}

@MainActor
final class EditorSession: ObservableObject {
    @Published private(set) var state: EditorState
    @Published private(set) var preview: NSImage
    @Published var tool: EditorTool = .arrow
    @Published var color: RGBAColor = .red
    @Published var lineWidth = 5.0
    @Published var fontSize = 28.0
    @Published var textValue = "Текст"

    let item: CaptureItem
    let windowImageSize: CGSize
    private unowned let model: AppModel
    private let baseImage: CGImage
    private var nextCounter: Int

    init?(item: CaptureItem, model: AppModel) {
        let document = model.history.loadDocument(for: item)
        let sourceURL = model.history.sourceImageURL(for: item, document: document)
        guard let image = NSImage(contentsOf: sourceURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.item = item
        self.windowImageSize = image.size
        self.model = model
        self.baseImage = cgImage
        self.state = EditorState(document: document)
        self.preview = NSImage(
            cgImage: cgImage,
            size: CGSize(width: cgImage.width, height: cgImage.height)
        )
        self.nextCounter = (document.annotations.compactMap(\.counter).max() ?? 0) + 1
        if !document.annotations.isEmpty {
            refreshPreview()
        }
    }

    var imageSize: CGSize { CGSize(width: baseImage.width, height: baseImage.height) }

    func makeDraft(
        start: NormalizedPoint,
        end: NormalizedPoint,
        points: [NormalizedPoint]
    ) -> Annotation? {
        makeAnnotation(start: start, end: end, points: points, minimumRectSize: 0)
    }

    func add(start: NormalizedPoint, end: NormalizedPoint, points: [NormalizedPoint]) {
        guard let annotation = makeAnnotation(
            start: start,
            end: end,
            points: points,
            minimumRectSize: 0.002
        ) else { return }
        state.add(annotation)
        if tool == .counter { nextCounter += 1 }
        refreshPreview()
    }

    private func makeAnnotation(
        start: NormalizedPoint,
        end: NormalizedPoint,
        points: [NormalizedPoint],
        minimumRectSize: Double
    ) -> Annotation? {
        let style = AnnotationStyle(color: color, lineWidth: lineWidth, fontSize: fontSize)
        let effectiveStyle = tool == .highlighter
            ? AnnotationStyle(color: .yellow, lineWidth: lineWidth)
            : style
        return AnnotationDraftBuilder.make(
            kind: tool.annotationKind,
            start: start,
            end: end,
            points: points,
            style: effectiveStyle,
            text: textValue,
            counter: nextCounter,
            minimumRectSize: minimumRectSize
        )
    }

    func undo() {
        state.undo()
        refreshPreview()
    }

    func redo() {
        state.redo()
        refreshPreview()
    }

    func deleteSelected() {
        state.deleteSelected()
        refreshPreview()
    }

    func clear() {
        state.clear()
        refreshPreview()
    }

    @discardableResult
    func save() -> Bool {
        do {
            let rendered = try AnnotationRenderer.render(baseImage: baseImage, document: state.document)
            try model.history.saveRendered(rendered, document: state.document, for: item)
            model.statusMessage = "Правки сохранены"
            return true
        } catch {
            model.present(error)
            return false
        }
    }

    @discardableResult
    func copy() -> Bool {
        guard save() else { return false }
        return model.copy(item)
    }

    func saveAs() {
        guard save() else { return }
        model.saveAs(item)
    }

    private func refreshPreview() {
        if let rendered = try? AnnotationRenderer.render(baseImage: baseImage, document: state.document) {
            preview = NSImage(
                cgImage: rendered,
                size: CGSize(width: rendered.width, height: rendered.height)
            )
        }
    }

}

extension Color {
    init(_ rgba: RGBAColor) {
        self.init(red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
