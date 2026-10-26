import ScreenshotCore
import SwiftUI

struct EditorCanvasView: View {
    @ObservedObject var session: EditorSession
    @State private var gestureStart: NormalizedPoint?
    @State private var gesturePoints: [NormalizedPoint] = []
    @State private var draftAnnotation: Annotation?
    @State private var zoomScale = 1.0
    @State private var magnificationStartScale: Double?

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 42
            let size = EditorCanvasLayout.contentSize(
                image: CanvasSize(
                    width: Double(session.imageSize.width),
                    height: Double(session.imageSize.height)
                ),
                availableWidth: Double(proxy.size.width),
                horizontalPadding: Double(padding)
            )
            let zoomedSize = EditorZoomPolicy.contentSize(base: size, scale: zoomScale)
            let canvasSize = CGSize(width: CGFloat(zoomedSize.width), height: CGFloat(zoomedSize.height))
            ZStack {
                Color.black.opacity(0.12)
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: session.preview)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .shadow(color: .black.opacity(0.24), radius: 16, y: 6)
                        .overlay {
                            ZStack {
                                if let draftAnnotation {
                                    AnnotationDraftOverlay(
                                        annotation: draftAnnotation,
                                        imageSize: session.imageSize
                                    )
                                }
                                Rectangle()
                                    .fill(.clear)
                                    .contentShape(Rectangle())
                                    .gesture(drawingGesture(size: canvasSize))
                                if session.tool == .text {
                                    textSelectionOverlay(size: canvasSize)
                                }
                            }
                        }
                        .simultaneousGesture(magnificationGesture)
                        .padding(padding)
                        .frame(
                            minWidth: proxy.size.width,
                            minHeight: proxy.size.height,
                            alignment: .center
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func textSelectionOverlay(size: CGSize) -> some View {
        let canvas = CanvasSize(width: session.imageSize.width, height: session.imageSize.height)
        let scale = size.width / max(session.imageSize.width, 1)
        return ForEach(session.state.document.annotations.filter { $0.kind == .text }) { annotation in
            if let bounds = AnnotationTextLayout.bounds(for: annotation, canvasSize: canvas) {
                let target = CGRect(
                    x: bounds.minX * scale, y: bounds.minY * scale,
                    width: bounds.width * scale, height: bounds.height * scale
                ).insetBy(dx: -4, dy: -4)
                Button {
                    session.selectText(annotation.id)
                } label: {
                    Rectangle()
                        .fill(.clear)
                        .overlay {
                            if session.state.selectedAnnotationID == annotation.id {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: target.width, height: target.height)
                .position(x: target.midX, y: target.midY)
                .accessibilityLabel("Редактировать текст: \(annotation.text ?? "")")
                .help("Нажмите, чтобы изменить текст в верхнем поле")
            }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let startScale = magnificationStartScale ?? zoomScale
                if magnificationStartScale == nil {
                    magnificationStartScale = startScale
                }
                zoomScale = EditorZoomPolicy.scale(
                    startScale: startScale,
                    magnification: Double(value.magnification)
                )
            }
            .onEnded { value in
                let startScale = magnificationStartScale ?? zoomScale
                zoomScale = EditorZoomPolicy.scale(
                    startScale: startScale,
                    magnification: Double(value.magnification)
                )
                magnificationStartScale = nil
            }
    }

    private func drawingGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = normalized(value.location, size: size)
                if gestureStart == nil {
                    let start = normalized(value.startLocation, size: size)
                    gestureStart = start
                    gesturePoints = [start]
                }
                if gesturePoints.last != point { gesturePoints.append(point) }
                if let start = gestureStart {
                    draftAnnotation = session.makeDraft(start: start, end: point, points: gesturePoints)
                }
            }
            .onEnded { value in
                let start = gestureStart ?? normalized(value.startLocation, size: size)
                let end = normalized(value.location, size: size)
                if gesturePoints.last != end { gesturePoints.append(end) }
                session.add(start: start, end: end, points: gesturePoints)
                draftAnnotation = nil
                gestureStart = nil
                gesturePoints.removeAll(keepingCapacity: true)
            }
    }

    private func normalized(_ point: CGPoint, size: CGSize) -> NormalizedPoint {
        NormalizedPoint(
            x: min(1, max(0, point.x / max(size.width, 1))),
            y: min(1, max(0, point.y / max(size.height, 1)))
        )
    }

}
