import SwiftUI
import SwiftData

/// Full-screen annotation editor sheet. Combines waveform display, silence detection,
/// marker management, and ayah assignment into one flow.
struct AnnotationEditorView: View {

    let recording: Recording

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var vm: AnnotationEditorViewModel
    @State private var selectedMarker: AyahMarker?
    @State private var showAutoDetectOptions = false
    @State private var saveError: Error?
    @State private var selectedTab: EditorTab = .tags
    @State private var autoAssignEnabled = false
    @State private var waveformScrollPosition = ScrollPosition(edge: .leading)

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

    // Width of the scrollable waveform content
    private var waveformContentWidth: CGFloat {
        max(UIScreen.main.bounds.width,
            UIScreen.main.bounds.width * CGFloat(recording.safeDuration / 60))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                waveformSection
                Divider()
                previewControls
                Divider()
                tabPicker
                Divider()
                tabContent
            }
            .navigationTitle(recording.safeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task {
                await vm.loadWaveform()
                // Re-editing: reconstruct markers from saved segments so previous work is visible
                let segments = recording.segments ?? []
                if recordingMarkers.isEmpty && !segments.isEmpty {
                    vm.reconstructMarkers(from: segments, context: context)
                }
            }
            .onDisappear { vm.stopPreview() }
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
                    onDelete: {
                        vm.deleteMarker(marker, context: context)
                    }
                )
            }
            .alert("Save Failed", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError?.localizedDescription ?? "")
            }
        }
    }

    // MARK: - Waveform section

    private var waveformSection: some View {
        Group {
            if vm.isLoadingWaveform {
                ProgressView("Analyzing audio…")
                    .frame(height: 120)
            } else if let error = vm.waveformError {
                Label(error.localizedDescription, systemImage: "waveform.slash")
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
            } else {
                let halfScreen = (UIScreen.main.bounds.width - 24) / 2  // 24 = 2 × 12pt horizontal padding
                ZStack {
                    // Scrollable waveform with half-screen padding on each side so the
                    // fixed center cursor can represent positions 0…duration.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: halfScreen, height: 120)
                            WaveformView(
                                amplitudes: vm.amplitudes,
                                duration: recording.safeDuration,
                                markers: recordingMarkers,
                                onTap: { seconds in
                                    vm.seekPreview(to: seconds)
                                },
                                onMarkerMoved: { marker, seconds in
                                    vm.moveMarker(marker, to: seconds)
                                },
                                onMarkerSelected: { marker in
                                    if let seconds = marker.positionSeconds {
                                        vm.seekPreview(to: seconds)
                                        scrollWaveformTo(seconds)
                                    }
                                }
                            )
                            .frame(width: waveformContentWidth)
                            Color.clear.frame(width: halfScreen, height: 120)
                        }
                    }
                    .scrollPosition($waveformScrollPosition)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.x
                    } action: { _, offset in
                        guard !vm.isPreviewPlaying, waveformContentWidth > 0 else { return }
                        let ratio = max(0, min(1.0, offset / waveformContentWidth))
                        vm.seekPreview(to: ratio * recording.safeDuration)
                    }
                    .onChange(of: vm.previewPosition) { _, newPos in
                        guard vm.isPreviewPlaying, recording.safeDuration > 0 else { return }
                        let targetX = CGFloat(newPos / recording.safeDuration) * waveformContentWidth
                        waveformScrollPosition = ScrollPosition(x: targetX)
                    }

                    // Fixed cursor always at the horizontal center of the viewport
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 2, height: 120)
                        .allowsHitTesting(false)
                }
                .frame(height: 120)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Preview controls

    private var previewControls: some View {
        HStack(spacing: 16) {
            Button {
                vm.togglePreview()
            } label: {
                Image(systemName: vm.isPreviewPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }

            if vm.previewDuration > 0 {
                Slider(
                    value: Binding(
                        get: { vm.previewPosition },
                        set: { vm.seekPreview(to: $0) }
                    ),
                    in: 0...max(1, vm.previewDuration)
                )
                Text(timeString(vm.previewPosition))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            } else {
                Spacer()
                Text(timeString(recording.safeDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Auto-assign toggle
            Button {
                autoAssignEnabled.toggle()
            } label: {
                Image(systemName: autoAssignEnabled ? "bookmark.circle.fill" : "bookmark.circle")
                    .font(.title2)
                    .foregroundStyle(autoAssignEnabled ? Color.accentColor : Color.secondary)
            }

            // Add marker at current playback position
            Button {
                addMarkerAtCurrentPosition()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func scrollWaveformTo(_ seconds: Double) {
        guard recording.safeDuration > 0 else { return }
        // The waveform content has halfScreen padding on each side, so scroll offset
        // maps directly: offset 0 = time 0, offset waveformContentWidth = end of audio.
        let targetX = CGFloat(seconds / recording.safeDuration) * waveformContentWidth
        let clampedX = max(0, min(targetX, waveformContentWidth))
        withAnimation(.easeInOut(duration: 0.3)) {
            waveformScrollPosition = ScrollPosition(x: clampedX)
        }
    }

    private func addMarkerAtCurrentPosition() {
        let pos = vm.previewPosition
        let newMarker = vm.addMarker(at: pos, context: context)

        guard autoAssignEnabled else { return }

        // Find the last confirmed marker with an ayah that sits before this position
        let prevConfirmed = recordingMarkers
            .filter { ($0.positionSeconds ?? 0) < pos && $0.assignedSurah != nil && $0.assignedAyah != nil }
            .last

        if let prev = prevConfirmed,
           let prevSurah = prev.assignedSurah,
           let prevAyah = prev.assignedAyah {
            let prevRef = AyahRef(surah: prevSurah, ayah: prevAyah)
            let nextRef = QuranMetadataService.shared.ayah(after: prevRef)
            // End ayah = ayah just recited (prev's start); start ayah = next consecutive ayah
            vm.assignAyah(nextRef, endRef: prevRef, to: newMarker, context: context)
        }
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(EditorTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .tags:
            markersList
        case .ayahPlayer:
            ayahPlayerList
        }
    }

    // MARK: - Tags tab (markers list)

    private var markersList: some View {
        List {
            if !vm.amplitudes.isEmpty {
                autoDetectRow
            }

            if recordingMarkers.isEmpty {
                ContentUnavailableView(
                    "No Markers",
                    systemImage: "pin.slash",
                    description: Text("Tap ＋ to place a marker at the current position, or use auto-detect.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(recordingMarkers, id: \.id) { marker in
                    markerRow(marker)
                }
                .onDelete { indexSet in
                    for i in indexSet {
                        vm.deleteMarker(recordingMarkers[i], context: context)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var autoDetectRow: some View {
        Section {
            DisclosureGroup("Silence Detection", isExpanded: $showAutoDetectOptions) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Threshold")
                            .font(.caption)
                        Slider(value: $vm.silenceThreshold, in: 0.01...0.15, step: 0.005)
                        Text(String(format: "%.3f", vm.silenceThreshold))
                            .font(.caption.monospacedDigit())
                            .frame(width: 40)
                    }
                    Button {
                        vm.runAutoDetect(markers: recordingMarkers, context: context)
                    } label: {
                        Label(vm.isRunningAutoDetect ? "Detecting…" : "Detect Silences",
                              systemImage: "waveform.path.ecg")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isRunningAutoDetect)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func markerRow(_ marker: AyahMarker) -> some View {
        HStack {
            // Tapping the label area scrolls the waveform to this marker
            Button {
                if let seconds = marker.positionSeconds {
                    vm.seekPreview(to: seconds)
                    scrollWaveformTo(seconds)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    // Time range
                    HStack(spacing: 4) {
                        Text(timeString(marker.positionSeconds ?? 0))
                            .font(.subheadline.monospacedDigit())
                        if let endPos = marker.endPositionSeconds {
                            Text("→ \(timeString(endPos))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    // Ayah assignment (end ayah = what ended here; start ayah = what starts here)
                    if marker.isConfirmed == true {
                        let metadata = QuranMetadataService.shared
                        let hasEnd = marker.assignedEndSurah != nil && marker.assignedEndAyah != nil
                        let hasStart = marker.assignedSurah != nil && marker.assignedAyah != nil
                        if hasEnd, let eS = marker.assignedEndSurah, let eA = marker.assignedEndAyah,
                           hasStart, let sS = marker.assignedSurah, let sA = marker.assignedAyah {
                            Text("\(metadata.surahName(eS)) \(eS):\(eA) ends · \(sS):\(sA) starts")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if hasEnd, let eS = marker.assignedEndSurah, let eA = marker.assignedEndAyah {
                            Text("\(metadata.surahName(eS)) \(eS):\(eA) ends")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if hasStart, let sS = marker.assignedSurah, let sA = marker.assignedAyah {
                            Text("\(metadata.surahName(sS)) \(sS):\(sA) starts")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text("Boundary (no ayah)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Unassigned")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button("Assign") { selectedMarker = marker }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - Ayah Player tab

    /// Pairs of (startMarker, closingEndMarker) for every fully-bounded segment.
    /// A segment without a subsequent end-ayah marker is not shown (it has no defined close).
    private var playableSegments: [(start: AyahMarker, end: AyahMarker)] {
        recordingMarkers
            .filter { $0.assignedSurah != nil && $0.assignedAyah != nil }
            .compactMap { startMarker in
                let startPos = startMarker.positionSeconds ?? 0
                guard let endMarker = recordingMarkers.first(where: {
                    ($0.positionSeconds ?? 0) > startPos && $0.assignedEndSurah != nil
                }) else { return nil }
                return (start: startMarker, end: endMarker)
            }
    }

    private var ayahPlayerList: some View {
        let segments = playableSegments
        return List {
            if segments.isEmpty {
                ContentUnavailableView(
                    "No Complete Segments",
                    systemImage: "music.note.list",
                    description: Text("Each segment needs a start ayah on one marker and an end ayah on the next.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(segments, id: \.start.id) { pair in
                    ayahPlayerRow(pair.start, endMarker: pair.end)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func ayahPlayerRow(_ startMarker: AyahMarker, endMarker: AyahMarker) -> some View {
        let start = startMarker.positionSeconds ?? 0
        let end = endMarker.positionSeconds ?? recording.safeDuration
        let isPlaying = vm.isPreviewPlaying
            && vm.previewPosition >= start
            && vm.previewPosition < end

        HStack {
            VStack(alignment: .leading, spacing: 3) {
                if let sS = startMarker.assignedSurah, let sA = startMarker.assignedAyah,
                   let eS = endMarker.assignedEndSurah, let eA = endMarker.assignedEndAyah {
                    let meta = QuranMetadataService.shared
                    if sS == eS {
                        Text("\(meta.surahName(sS)) \(sS):\(sA)–\(eA)")
                            .font(.headline)
                    } else {
                        Text("\(meta.surahName(sS)) \(sS):\(sA) – \(meta.surahName(eS)) \(eS):\(eA)")
                            .font(.headline)
                    }
                }
                Text("\(timeString(start)) – \(timeString(end))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if isPlaying {
                    vm.stopPreview()
                } else {
                    vm.playSegment(from: start, to: end)
                }
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isPlaying ? .red : Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                do {
                    try vm.saveSegments(markers: recordingMarkers, context: context)
                    dismiss()
                } catch {
                    saveError = error
                }
            }
            .fontWeight(.semibold)
            .disabled(recordingMarkers.isEmpty)
        }
    }

    // MARK: - Helpers

    private func timeString(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Supporting types

enum EditorTab: String, CaseIterable {
    case tags = "Tags"
    case ayahPlayer = "Ayah Player"
}

