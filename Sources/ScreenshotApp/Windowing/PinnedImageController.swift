import AppKit
import ScreenshotCore
import SwiftUI

@MainActor
final class PinnedImageController: NSObject, NSWindowDelegate {
    private var windows: [NSWindow] = []

    func pin(item: CaptureItem) {
        guard let image = NSImage(contentsOf: item.imageURL) else { return }
        let maxWidth: CGFloat = 520
        let ratio = image.size.height / max(image.size.width, 1)
        let width = min(maxWidth, max(220, image.size.width))
        let height = width * ratio
        let window = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Закрепленный снимок"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.contentView = NSHostingView(rootView: PinnedImageView(image: image))
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        windows.removeAll { !$0.isVisible }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === closingWindow }
    }
}

private struct PinnedImageView: View {
    let image: NSImage
    @State private var opacity = 1.0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .opacity(opacity)
            HStack(spacing: 6) {
                Image(systemName: "circle.lefthalf.filled")
                Slider(value: $opacity, in: 0.25...1)
                    .frame(width: 80)
            }
            .help("Прозрачность закрепленного снимка")
            .padding(8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(10)
        }
        .background(.black.opacity(0.04))
    }
}
