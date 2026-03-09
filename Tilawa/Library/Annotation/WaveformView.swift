import SwiftUI

/// Canvas-based waveform display with draggable marker overlays and crop region shading.
/// The playback cursor is rendered as a fixed overlay by the parent (AnnotationEditorView).
struct WaveformView: View {

    let amplitudes: [Float]
    let duration: Double
    let markers: [AyahMarker]

    var onMarkerMoved: (AyahMarker, Double) -> Void
    var onMarkerSelected: (AyahMarker) -> Void   // tap marker line → scrub to position
    var onMarkerEdit: (AyahMarker) -> Void        // pencil button → open assignment sheet

    private let barWidth: CGFloat = 2.5

    /// For each marker ID, returns (occurrenceNumber, totalCount) when the marker's ayah
    /// appears more than once among confirmed ayah markers, ordered by position.
    private var occurrenceMap: [UUID: (number: Int, total: Int)] {
        let confirmed = markers
            .filter { $0.isConfirmed == true && $0.resolvedMarkerType == .ayah && $0.assignedSurah != nil && $0.assignedAyah != nil }
            .sorted { ($0.positionSeconds ?? 0) < ($1.positionSeconds ?? 0) }

        // Group by AyahRef string key
        var groups: [String: [UUID]] = [:]
        for m in confirmed {
            let key = "\(m.assignedSurah!)-\(m.assignedAyah!)"
            groups[key, default: []].append(m.id ?? UUID())
        }

        var result: [UUID: (number: Int, total: Int)] = [:]
        for (_, ids) in groups where ids.count > 1 {
            for (i, id) in ids.enumerated() {
                result[id] = (i + 1, ids.count)
            }
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Waveform bars + crop region shading
                Canvas { ctx, size in
                    drawCropRegions(ctx: ctx, size: size)
                    drawWaveform(ctx: ctx, size: size)
                }

                // Marker overlays
                ForEach(markers, id: \.id) { marker in
                    markerOverlay(for: marker, size: geo.size)
                }
            }
            .coordinateSpace(name: "waveform")
            .contentShape(Rectangle())
        }
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

    private func drawCropRegions(ctx: GraphicsContext, size: CGSize) {
        guard duration > 0 else { return }
        let regions = AnnotationEditorViewModel.computeCropRegions(
            from: markers, totalDuration: duration
        )
        for region in regions {
            let x1 = CGFloat(region.start / duration) * size.width
            let x2 = CGFloat(region.end / duration) * size.width
            let rect = CGRect(x: x1, y: 0, width: x2 - x1, height: size.height)
            ctx.fill(Path(rect), with: .color(Color.purple.opacity(0.25)))
        }
    }

    // MARK: - Marker overlays

    @ViewBuilder
    private func markerOverlay(for marker: AyahMarker, size: CGSize) -> some View {
        let x: CGFloat = duration > 0
            ? CGFloat((marker.positionSeconds ?? 0) / duration) * size.width
            : 0
        let color = marker.displayColor

        // Full-height vertical line (tap to scrub, not draggable)
        Rectangle()
            .fill(color)
            .frame(width: 2, height: size.height)
            .overlay(alignment: .top) {
                // Drag handle + edit button at top of marker
                VStack(spacing: 2) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .bold))
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                    if let occ = marker.id.flatMap({ occurrenceMap[$0] }) {
                        Text("\(occ.number)")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 16, height: 16)
                            .background(color.opacity(0.3), in: Circle())
                    }
                }
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: Capsule())
                .offset(y: 4)
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named("waveform"))
                        .onChanged { value in
                            let newSeconds = max(0, min(duration,
                                Double(value.location.x / size.width) * duration))
                            onMarkerMoved(marker, newSeconds)
                        }
                )
                .onTapGesture {
                    onMarkerEdit(marker)
                }
            }
            .contentShape(Rectangle().size(width: 24, height: size.height).offset(x: -11))
            .onTapGesture {
                onMarkerSelected(marker)
            }
            .offset(x: x - 1)
    }
}
