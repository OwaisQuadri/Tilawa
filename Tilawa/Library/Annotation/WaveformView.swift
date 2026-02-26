import SwiftUI

/// Canvas-based waveform display with draggable marker pins.
/// The playback cursor is rendered as a fixed overlay by the parent (AnnotationEditorView).
struct WaveformView: View {

    let amplitudes: [Float]
    let duration: Double
    let markers: [AyahMarker]

    var onTap: (Double) -> Void          // seconds at tap location
    var onMarkerMoved: (AyahMarker, Double) -> Void
    var onMarkerSelected: (AyahMarker) -> Void

    private let barWidth: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Waveform bars
                Canvas { ctx, size in
                    drawWaveform(ctx: ctx, size: size)
                }

                // Marker pins — drag gesture restricted to the ball via coordinateSpace
                ForEach(markers, id: \.id) { marker in
                    markerPin(for: marker, width: geo.size.width)
                }
            }
            .coordinateSpace(name: "waveform")
            .contentShape(Rectangle())
            .gesture(tapGesture(width: geo.size.width))
        }
        .frame(height: 120)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Drawing

    private func drawWaveform(ctx: GraphicsContext, size: CGSize) {
        guard !amplitudes.isEmpty else { return }
        let barCount = amplitudes.count
        let step = size.width / CGFloat(barCount)
        let midY = size.height / 2

        for (i, amp) in amplitudes.enumerated() {
            let x = CGFloat(i) * step + step / 2
            let barHeight = max(2, CGFloat(amp) * size.height * 0.85)
            let rect = CGRect(x: x - barWidth / 2,
                              y: midY - barHeight / 2,
                              width: barWidth,
                              height: barHeight)
            ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                     with: .color(.accentColor.opacity(0.6)))
        }
    }

    // MARK: - Marker pins

    @ViewBuilder
    private func markerPin(for marker: AyahMarker, width: CGFloat) -> some View {
        let x: CGFloat = duration > 0
            ? CGFloat((marker.positionSeconds ?? 0) / duration) * width
            : 0
        let isConfirmed = marker.isConfirmed ?? false
        let color: Color = isConfirmed ? .green : .orange

        VStack(spacing: 0) {
            // Ball — the only drag target
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named("waveform"))
                        .onChanged { value in
                            let newSeconds = max(0, min(duration,
                                Double(value.location.x / width) * duration))
                            onMarkerMoved(marker, newSeconds)
                        }
                )
            // Line body — visual only, no hit testing
            Rectangle()
                .fill(color)
                .frame(width: 2)
                .allowsHitTesting(false)
        }
        .offset(x: x - 7)
        .onTapGesture { onMarkerSelected(marker) }
    }

    // MARK: - Tap gesture

    private func tapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let tapSeconds = Double(value.location.x / width) * duration
                if let nearby = nearestMarker(to: tapSeconds, width: width) {
                    onMarkerSelected(nearby)
                } else {
                    onTap(tapSeconds)
                }
            }
    }

    private func nearestMarker(to seconds: Double, width: CGFloat) -> AyahMarker? {
        guard duration > 0 else { return nil }
        let tapX = CGFloat(seconds / duration) * width
        let snapThreshold: CGFloat = 16
        return markers.min(by: {
            let x0 = CGFloat(($0.positionSeconds ?? 0) / duration) * width
            let x1 = CGFloat(($1.positionSeconds ?? 0) / duration) * width
            return abs(x0 - tapX) < abs(x1 - tapX)
        }).flatMap { marker in
            let markerX = CGFloat((marker.positionSeconds ?? 0) / duration) * width
            return abs(markerX - tapX) < snapThreshold ? marker : nil
        }
    }
}
