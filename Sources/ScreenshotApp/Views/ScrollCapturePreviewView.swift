import AppKit
import ScreenshotCore
import SwiftUI

/// Панель-рельс сбоку от выбранной рамки: показывает не «объём прокрутки»,
/// а фактическую склейку, которая уйдёт в итоговый PNG.
struct ScrollCapturePreviewView: View {
    @ObservedObject var controller: ScrollCaptureController

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Длинный снимок")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(controller.frameCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            preview

            Text(badge.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(badgeColor.opacity(0.16), in: Capsule())
                .accessibilityLabel("Состояние: \(badge.title)")
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
        }
        .environment(\.appearsActive, true)
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let image = controller.previewImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Накоплено кадров: \(controller.frameCount)")
            } else {
                Text("Первый кадр появится после «Начать»")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            // Нижний край превью - это место, куда придёт следующий принятый кадр.
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(controller.previewImage == nil ? 0 : 0.9))
                .frame(height: 2)
                .padding(.horizontal, 2)
        }
    }

    private var badge: ScrollCapturePreviewBadge { controller.previewBadge }

    private var badgeColor: Color {
        switch badge.tone {
        case .neutral: .secondary
        case .aligning: .blue
        case .accepted: .green
        case .warning: .orange
        case .working: .cyan
        }
    }
}
