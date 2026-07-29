import AppKit
import SwiftUI

struct ScrollCaptureControlsView: View {
    @ObservedObject var controller: ScrollCaptureController

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Прокручиваемый снимок", systemImage: "arrow.up.and.down.text.horizontal")
                    .font(.headline)
                Spacer()
                Text(controller.hasStarted ? "\(controller.frameCount) кадр." : "Область выбрана")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                Text("Esc - отмена")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button(action: controller.cancel) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .help("Отменить снимок с прокруткой")
                    .accessibilityLabel("Отменить снимок с прокруткой")
            }
            HStack(spacing: 8) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                Text(controller.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(controller.message)
            if controller.hasStarted {
                HStack(spacing: 10) {
                    Button("Отмена", action: controller.cancel)
                    Button("Убрать кадр", action: controller.undoFrame)
                        .disabled(controller.frameCount <= 1)
                    Spacer()
                    Button(controller.isAutoScrolling ? "Стоп" : "Крутить само", action: controller.toggleAutoScroll)
                        .disabled(!controller.canAutoScroll)
                        .help("Приложение само прокручивает страницу шагом в треть области")
                    Button(controller.isPaused ? "Продолжить" : "Пауза", action: controller.togglePause)
                        .disabled(!controller.isCapturing)
                    Button("Готово", action: controller.finish)
                        .buttonStyle(.borderedProminent)
                        .disabled(!controller.canFinish)
                }
            } else {
                HStack(spacing: 12) {
                    Button("Отмена", action: controller.cancel)
                    Spacer()
                    Button("Начать", action: controller.start)
                        .buttonStyle(.borderedProminent)
                        .disabled(!controller.canStart)
                }
            }
        }
        .padding(14)
        .controlSize(.large)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        .onExitCommand { controller.cancel() }
        .environment(\.appearsActive, true)
    }

    private var statusSymbol: String {
        switch controller.feedbackState {
        case .ready: "arrow.down.circle.fill"
        case .aligning: "viewfinder.circle"
        case .acceptedDown, .acceptedUp: "checkmark.circle.fill"
        case .needsOverlap: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch controller.feedbackState {
        case .ready: .cyan
        case .aligning: .blue
        case .acceptedDown, .acceptedUp: .green
        case .needsOverlap: .orange
        }
    }
}
