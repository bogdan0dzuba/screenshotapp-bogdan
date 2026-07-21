import SwiftUI

struct ScrollCaptureControlsView: View {
    @ObservedObject var controller: ScrollCaptureController

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Прокручиваемый снимок", systemImage: "arrow.up.and.down.text.horizontal")
                    .font(.headline)
                if controller.isProcessingFrame {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("Кадров: \(controller.frameCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: controller.cancel) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .help("Отменить снимок с прокруткой")
                    .accessibilityLabel("Отменить снимок с прокруткой")
            }
            Text(controller.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Убрать кадр", action: controller.undoFrame)
                    .disabled(controller.frameCount <= 1 || controller.isProcessingFrame)
                Spacer()
                Button(controller.isPaused ? "Продолжить" : "Пауза", action: controller.togglePause)
                    .disabled(controller.isProcessingFrame || !controller.isCapturing)
                Button("Готово", action: controller.finish)
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isProcessingFrame || !controller.isCapturing)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2)))
        .onExitCommand { controller.cancel() }
    }
}
