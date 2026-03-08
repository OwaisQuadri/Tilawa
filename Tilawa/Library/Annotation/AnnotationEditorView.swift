import SwiftUI
import SwiftData

/// Full-screen annotation editor sheet. Waveform fills the screen with marker overlays;
/// a fixed center cursor tracks playback position as the waveform scrolls underneath.
struct AnnotationEditorView: View {

    let recording: Recording

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var vm: AnnotationEditorViewModel
    @State private var selectedMarker: AyahMarker?
    @State private var saveError: Error?
    @State private var showFinalizeConfirm = false
    @State private var autoAssignEnabled = false
    @State private var waveformScrollPosition = ScrollPosition(edge: .leading)
    @State private var baseZoomLevel: CGFloat = 1.0
    @State private var isUserScrolling = false

    private let recordingId: UUID

    @Query private var markers: [AyahMarker]

    init(recording: Recording) {
        self.recording = recording
        self.recordingId = recording.id ?? UUID()
        _vm = State(initialValue: AnnotationEditorViewModel(recording: recording))
        _markers = Query(
            filter: #Predicate<AyahMarker> { $0.recording != nil },
            sort: \AyahMarker.positionSeconds
        )
    }

    private var recordingMarkers: [AyahMarker] {
        markers.filter { $0.recording?.id == recordingId }
            .sorted { ($0.positionSeconds ?? 0) < ($1.positionSeconds ?? 0) }
    }

    private var hasAnnotatedSegments: Bool {
        recordingMarkers.contains { $0.isConfirmed == true && $0.assignedSurah != nil }
    }

    private var hasCropRegion: Bool {
        !AnnotationEditorViewModel.computeCropRegions(
            from: recordingMarkers, totalDuration: recording.safeDuration
        ).isEmpty
    }

    // Width of the scrollable waveform content (zoom-adjusted)
    private var waveformContentWidth: CGFloat {
        let base = max(UIScreen.main.bounds.width,
                       UIScreen.main.bounds.width * CGFloat(recording.safeDuration / 60))
        return base * vm.zoomLevel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                waveformSection
                Divider()
                bottomToolbar
            }
            .navigationTitle(recording.safeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task {
                await vm.loadWaveform()
                let segments = recording.segments ?? []
                let hasAyahMarkers = recordingMarkers.contains { $0.resolvedMarkerType == .ayah }
                if !hasAyahMarkers && !segments.isEmpty {
                    vm.reconstructMarkers(from: segments, context: context)
                }
            }
            .onDisappear {
                vm.stopPreview()
                vm.cleanupUndoBackups()
            }
            .sheet(item: $selectedMarker) { marker in
                let pos = marker.positionSeconds ?? 0
                let prevRef: AyahRef? = recordingMarkers
                    .filter { ($0.positionSeconds ?? 0) < pos && $0.assignedSurah != nil && $0.assignedAyah != nil }
                    .last
                    .flatMap { m in
                        guard let s = m.assignedSurah, let a = m.assignedAyah else { return nil }
                        return AyahRef(surah: s, ayah: a)
                    }
                AyahAssignmentView(
                    marker: marker,
                    suggestedRef: prevRef,
                    onAssign: { startRef, endRef in
                        vm.assignAyah(startRef, endRef: endRef, to: marker, context: context)
                    },
                    onMarkerTypeChanged: { type in
                        marker.markerType = type.rawValue
                    },
                    onDelete: {
                        vm.deleteMarker(marker, context: context)
                    }
                )
            }
            .alert("Error", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError?.localizedDescription ?? "")
            }
            .alert("Finalize Recording", isPresented: $showFinalizeConfirm) {
                Button("Finalize", role: .destructive) {
                    Task {
                        do {
                            try await vm.finalizeRecording(markers: recordingMarkers, context: context)
                            dismiss()
                        } catch {
                            saveError = error
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This is an irreversible action. This will crop selected regions, remove audio not covered by markers, and concatenate remaining segments.")
            }
            .overlay {
                if vm.isProcessingEdit {
                    ZStack {
                        Color.black.opacity(0.3)
                        ProgressView(vm.processingMessage)
                            .padding()
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    // MARK: - Waveform section

    private var waveformSection: some View {
        Group {
            if vm.isLoadingWaveform {
                ProgressView("Analyzing audio…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.waveformError {
                Label(error.localizedDescription, systemImage: "waveform.slash")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let halfScreen = (UIScreen.main.bounds.width - 24) / 2
                ZStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: halfScreen)
                            WaveformView(
                                amplitudes: vm.amplitudes,
                                duration: recording.safeDuration,
                                markers: recordingMarkers,
                                onMarkerMoved: { marker, seconds in
                                    vm.moveMarker(marker, to: seconds)
                                },
                                onMarkerSelected: { marker in
                                    if let seconds = marker.positionSeconds {
                                        vm.seekPreview(to: seconds)
                                        scrollWaveformTo(seconds)
                                    }
                                },
                                onMarkerEdit: { marker in
                                    selectedMarker = marker
                                }
                            )
                            .frame(width: waveformContentWidth)
                            Color.clear.frame(width: halfScreen)
                        }
                    }
                    .scrollPosition($waveformScrollPosition)
                    .onScrollPhaseChange { oldPhase, newPhase in
                        if newPhase == .interacting {
                            isUserScrolling = true
                            // Pause playback when user starts dragging
                            if vm.isPreviewPlaying {
                                vm.wasPausedByScroll = true
                                vm.stopPreview()
                            }
                        } else if newPhase == .idle, oldPhase != .idle {
                            isUserScrolling = false
                            // Resume playback only if it was playing before the drag
                            if vm.wasPausedByScroll {
                                vm.wasPausedByScroll = false
                                vm.startPreview(from: vm.previewPosition)
                            }
                        }
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.x
                    } action: { _, offset in
                        // Only update position from scroll when user is actively scrolling (not during playback-driven scroll)
                        guard isUserScrolling, !vm.isZooming, waveformContentWidth > 0 else { return }
                        let ratio = max(0, min(1.0, offset / waveformContentWidth))
                        let seconds = ratio * recording.safeDuration
                        let snapped = seconds < 0.01 ? 0 : (seconds > recording.safeDuration - 0.01 ? recording.safeDuration : seconds)
                        vm.seekPreview(to: snapped)
                    }
                    .onChange(of: vm.previewPosition) { _, newPos in
                        guard vm.isPreviewPlaying, recording.safeDuration > 0 else { return }
                        let targetX = CGFloat(newPos / recording.safeDuration) * waveformContentWidth
                        waveformScrollPosition = ScrollPosition(x: targetX)
                    }
                    .simultaneousGesture(pinchToZoom)

                    // Fixed center cursor
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 2)
                        .allowsHitTesting(false)

                    // Current time label below cursor
                    VStack {
                        Spacer()
                        Text(timeString(vm.previewPosition))
                            .font(.title3.monospacedDigit().weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassEffect(.identity, in: Capsule())
                            .padding(.bottom, 8)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    // MARK: - Pinch to zoom

    private var pinchToZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                vm.isZooming = true
                let newZoom = max(0.5, min(5.0, baseZoomLevel * value.magnification))
                let currentPosition = vm.previewPosition
                vm.zoomLevel = newZoom
                // Re-anchor scroll to keep the cursor at the same time position
                let targetX = CGFloat(currentPosition / recording.safeDuration) * waveformContentWidth
                waveformScrollPosition = ScrollPosition(x: targetX)
            }
            .onEnded { _ in
                baseZoomLevel = vm.zoomLevel
                vm.isZooming = false
            }
    }

    // MARK: - Bottom toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            // Auto-marker toggle
            Button {
                autoAssignEnabled.toggle()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(autoAssignEnabled ? Color.accentColor : .secondary)
                    Text("Auto")
                        .font(.caption2)
                        .foregroundStyle(autoAssignEnabled ? Color.accentColor : .secondary)
                }
            }
            .frame(maxWidth: .infinity)

            // Undo last cut
            Button {
                Task {
                    do {
                        try await vm.undoLastCut(markers: recordingMarkers, context: context)
                    } catch {
                        saveError = error
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title2)
                        .foregroundStyle(vm.canUndo ? Color.accentColor : .secondary)
                    Text("Undo")
                        .font(.caption2)
                        .foregroundStyle(vm.canUndo ? Color.accentColor : .secondary)
                }
            }
            .disabled(!vm.canUndo || vm.isProcessingEdit)
            .frame(maxWidth: .infinity)

            // Redo last undone cut
            Button {
                Task {
                    do {
                        try await vm.redoLastCut(markers: recordingMarkers, context: context)
                    } catch {
                        saveError = error
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.title2)
                        .foregroundStyle(vm.canRedo ? Color.accentColor : .secondary)
                    Text("Redo")
                        .font(.caption2)
                        .foregroundStyle(vm.canRedo ? Color.accentColor : .secondary)
                }
            }
            .disabled(!vm.canRedo || vm.isProcessingEdit)
            .frame(maxWidth: .infinity)

            // Play / Pause
            Button {
                vm.togglePreview()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: vm.isPreviewPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                    Text(vm.isPreviewPlaying ? "Pause" : "Play")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)

            // Cut crop region
            Button {
                Task {
                    do {
                        try await vm.cutCropRegion(markers: recordingMarkers, context: context)
                    } catch {
                        saveError = error
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "scissors")
                        .font(.title2)
                        .foregroundStyle(hasCropRegion ? .red : .secondary)
                    Text("Cut")
                        .font(.caption2)
                        .foregroundStyle(hasCropRegion ? .red : .secondary)
                }
            }
            .disabled(!hasCropRegion || vm.isProcessingEdit)
            .frame(maxWidth: .infinity)

            // Add Marker
            Button {
                addMarkerAtCurrentPosition()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                    Text("Marker")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Back/Save") {
                autosave()
                dismiss()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Finalize") {
                showFinalizeConfirm = true
            }
            .fontWeight(.semibold)
            .disabled(!hasAnnotatedSegments || vm.isProcessingEdit)
        }
    }

    // MARK: - Actions

    private func autosave() {
        let ayahMarkers = recordingMarkers.filter { $0.resolvedMarkerType == .ayah }
        guard !ayahMarkers.isEmpty else { return }
        do {
            try vm.saveSegments(markers: ayahMarkers, context: context)
        } catch {
            saveError = error
        }
    }

    private func scrollWaveformTo(_ seconds: Double) {
        guard recording.safeDuration > 0 else { return }
        let targetX = CGFloat(seconds / recording.safeDuration) * waveformContentWidth
        let clampedX = max(0, min(targetX, waveformContentWidth))
        withAnimation(.easeInOut(duration: 0.3)) {
            waveformScrollPosition = ScrollPosition(x: clampedX)
        }
    }

    private func addMarkerAtCurrentPosition() {
        let pos = vm.previewPosition
        let newMarker = vm.addMarker(at: pos, context: context)

        // Carry-forward reciterID and riwayah from the last marker before this position
        let prevMarker = recordingMarkers.filter { ($0.positionSeconds ?? 0) < pos }.last
        newMarker.reciterID = prevMarker?.reciterID
        newMarker.riwayah   = prevMarker?.riwayah ?? Riwayah.hafs.rawValue

        guard autoAssignEnabled else { return }

        // Determine auto type based on last marker
        let autoType = vm.autoMarkerType(for: recordingMarkers)
        newMarker.markerType = autoType.rawValue

        if autoType != .ayah {
            newMarker.isConfirmed = true
            return
        }

        // Auto-assign ayah from previous confirmed ayah marker
        let prevConfirmed = recordingMarkers
            .filter { ($0.positionSeconds ?? 0) < pos && $0.assignedSurah != nil && $0.assignedAyah != nil }
            .last

        if let prev = prevConfirmed,
           let prevSurah = prev.assignedSurah,
           let prevAyah = prev.assignedAyah {
            let prevRef = AyahRef(surah: prevSurah, ayah: prevAyah)
            let nextRef = QuranMetadataService.shared.ayah(after: prevRef)
            vm.assignAyah(nextRef, endRef: prevRef, to: newMarker, context: context)
        }
    }

    // MARK: - Helpers

    private func timeString(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
