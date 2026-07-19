import ScreenshotCore
import SwiftUI

struct EditorView: View {
    @ObservedObject var session: EditorSession
    let copyAction: () -> Void

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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: session.undo) { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!session.state.canUndo)
                    .help("Отменить")
                Button(action: session.redo) { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!session.state.canRedo)
                    .help("Повторить")
                Divider().frame(height: 22)
                Text(session.tool.title).fontWeight(.semibold)
                if session.tool == .text {
                    TextField("Текст", text: $session.textValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                Spacer(minLength: 12)
                Button("Копировать", action: copyAction)
                    .keyboardShortcut("c", modifiers: .command)
                Button("Сохранить как…", action: session.saveAs)
                Button("Сохранить") { session.save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
            }
            .frame(minWidth: 680)
            .padding(.horizontal, 14)
        }
        .buttonStyle(.borderless)
        .frame(height: 48)
    }

    private var toolPalette: some View {
        VStack(spacing: 2) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    session.tool = tool
                } label: {
                    Image(systemName: tool.icon)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 36, height: 32)
                        .background(session.tool == tool ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help(tool.title)
            }
            Spacer()
            Button(action: session.clear) {
                Image(systemName: "trash")
                    .frame(width: 36, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Удалить все аннотации")
        }
        .padding(8)
        .frame(width: 52)
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
