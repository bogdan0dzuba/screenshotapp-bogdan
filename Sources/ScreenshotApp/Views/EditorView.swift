import AppKit
import ScreenshotCore
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var preferences: AppPreferences
    let copyAction: () -> Void
    @State private var draggedTool: EditorTool?
    @State private var hoveredTool: EditorTool?

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()
            HStack(spacing: 0) {
                toolPalette
                Divider()
                EditorCanvasView(session: session)
            }
            Divider()
            footer
        }
        .background(.regularMaterial)
    }

    private var editorToolbar: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: session.undo) { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!session.state.canUndo)
                        .help("Отменить")
                        .keyboardShortcut("z", modifiers: .command)
                    Button(action: session.redo) { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!session.state.canRedo)
                        .help("Повторить")
                    if session.tool == .text {
                        Divider().frame(height: 22)
                        TextField("Текст", text: $session.textValue)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                    }
                    Divider().frame(height: 22)
                    editorActions
                }
                .frame(minWidth: max(680, proxy.size.width - 28), alignment: .leading)
                .padding(.horizontal, 14)
            }
        }
        .buttonStyle(.borderless)
        .frame(height: 48)
    }

    private var editorActions: some View {
        HStack(spacing: 8) {
            Button(action: copyAction) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Копировать")
            .accessibilityLabel("Копировать")
            .keyboardShortcut("c", modifiers: .command)

            Button(action: session.saveAs) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Сохранить как…")
            .accessibilityLabel("Сохранить как…")

            Button {
                _ = session.save()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .help("Сохранить")
            .accessibilityLabel("Сохранить")
            .keyboardShortcut("s", modifiers: .command)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var toolPalette: some View {
        VStack(spacing: 2) {
            ForEach(preferences.editorToolOrder) { tool in
                let isHovered = hoveredTool == tool
                HStack(spacing: 0) {
                    Button {
                        session.tool = tool
                    } label: {
                        Image(systemName: tool.icon)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 34, height: 30)
                            .background(session.tool == tool ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tool.title)

                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10, height: 30)
                        .contentShape(Rectangle())
                        .opacity(isHovered ? 1 : 0)
                        .allowsHitTesting(isHovered)
                        .help("Перетащить инструмент «\(tool.title)»")
                        .onDrag {
                            draggedTool = tool
                            return NSItemProvider(object: NSString(string: tool.rawValue))
                        }
                }
                .frame(width: 44, height: 30)
                .contentShape(Rectangle())
                .help("\(tool.title). Наведите курсор на полоски и перетащите")
                .onHover { isInside in
                    if isInside {
                        hoveredTool = tool
                    } else if hoveredTool == tool {
                        hoveredTool = nil
                    }
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ToolReorderDropDelegate(
                        target: tool,
                        draggedTool: $draggedTool,
                        move: { source, target in
                            preferences.moveEditorTool(source, onto: target)
                        }
                    )
                )
            }
            Spacer()
            Button(action: session.clear) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Удалить все аннотации")
        }
        .padding(6)
        .frame(width: 56)
    }

    private var footer: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Text("Цвет")
                    .foregroundStyle(.secondary)
                ForEach([RGBAColor.red, .blue, .yellow, .black, .white], id: \.self) { color in
                    Button {
                        session.color = color
                    } label: {
                        Circle()
                            .fill(Color(color))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(session.color == color ? Color.accentColor : .secondary.opacity(0.35), lineWidth: session.color == color ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 22)
                Text("Толщина")
                    .foregroundStyle(.secondary)
                Slider(value: $session.lineWidth, in: 2...24)
                    .frame(width: 130)
                Text("\(Int(session.lineWidth))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 22)
                if session.tool == .text || session.tool == .counter {
                    Text("Размер")
                        .foregroundStyle(.secondary)
                    Slider(value: $session.fontSize, in: 14...72)
                        .frame(width: 110)
                }
                Spacer(minLength: 12)
                Text("Слои: \(session.state.document.annotations.count)")
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 680)
            .padding(.horizontal, 14)
        }
        .frame(height: 44)
    }
}

private struct ToolReorderDropDelegate: DropDelegate {
    let target: EditorTool
    @Binding var draggedTool: EditorTool?
    let move: (EditorTool, EditorTool) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedTool, draggedTool != target else { return }
        move(draggedTool, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTool = nil
        return true
    }
}
