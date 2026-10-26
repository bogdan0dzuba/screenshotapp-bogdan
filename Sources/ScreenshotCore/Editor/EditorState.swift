import Foundation

public struct EditorState: Sendable {
    public private(set) var document: EditorDocument
    public private(set) var selectedAnnotationID: UUID?
    private var undoStack: [EditorDocument]
    private var redoStack: [EditorDocument]
    private var textEditingAnnotationID: UUID?

    public init(document: EditorDocument) {
        self.document = document
        self.selectedAnnotationID = nil
        self.undoStack = []
        self.redoStack = []
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func add(_ annotation: Annotation) {
        checkpoint()
        document.annotations.append(annotation)
        selectedAnnotationID = annotation.id
    }

    public mutating func replace(_ annotation: Annotation) {
        guard let index = document.annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        checkpoint()
        document.annotations[index] = annotation
        selectedAnnotationID = annotation.id
    }

    public mutating func select(_ id: UUID?) {
        endTextEditing()
        selectedAnnotationID = id
    }

    public mutating func updateSelectedText(_ text: String) {
        guard let selectedAnnotationID,
              let index = document.annotations.firstIndex(where: { $0.id == selectedAnnotationID }),
              document.annotations[index].kind == .text,
              document.annotations[index].text != text else { return }
        if textEditingAnnotationID != selectedAnnotationID {
            checkpoint()
            textEditingAnnotationID = selectedAnnotationID
        }
        document.annotations[index].text = text
    }

    public mutating func endTextEditing() {
        textEditingAnnotationID = nil
    }

    public mutating func deleteSelected() {
        guard let selectedAnnotationID,
              document.annotations.contains(where: { $0.id == selectedAnnotationID }) else { return }
        checkpoint()
        document.annotations.removeAll { $0.id == selectedAnnotationID }
        self.selectedAnnotationID = nil
    }

    public mutating func clear() {
        guard !document.annotations.isEmpty else { return }
        checkpoint()
        document.annotations.removeAll()
        selectedAnnotationID = nil
    }

    public mutating func undo() {
        endTextEditing()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        selectedAnnotationID = nil
    }

    public mutating func redo() {
        endTextEditing()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        selectedAnnotationID = nil
    }

    private mutating func checkpoint() {
        endTextEditing()
        undoStack.append(document)
        redoStack.removeAll()
    }
}
