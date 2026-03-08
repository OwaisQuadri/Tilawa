import Foundation
import SwiftData
import AVFoundation

/// Drives all state for the annotation editor.
/// Does NOT hold a ModelContext — receives it from the SwiftUI environment.
@Observable
@MainActor
final class AnnotationEditorViewModel {

    let recording: Recording

    // MARK: - Waveform

    var amplitudes: [Float] = []
    var isLoadingWaveform = false
    var waveformError: Error?

    // MARK: - Preview playback (lightweight AVAudioPlayer, independent of PlaybackEngine)

    var previewPosition: Double = 0   // seconds
    var isPreviewPlaying = false
    var previewDuration: Double = 0

    private var audioPlayer: AVAudioPlayer?
    private var positionUpdateTimer: Timer?
    private var segmentEndTime: Double?

    // MARK: - Edit operation state

    var isProcessingEdit = false
    var processingMessage = "Finalizing…"
    var editError: Error?

    private let audioEditor = AudioEditingService()

    // MARK: - Undo stack for cuts

    struct CutSnapshot {
        let backupURL: URL
        let duration: Double
        let markerPositions: [(id: UUID, position: Double)]
    }
    var undoStack: [CutSnapshot] = []
    var redoStack: [CutSnapshot] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Zoom

    var zoomLevel: CGFloat = 1.0
    var isZooming = false

    // MARK: - Scroll interaction during playback

    /// When the user drags the waveform during playback, we pause and track that state
    /// so we can resume from the new position when they release.
    var wasPausedByScroll = false

    // MARK: - Waveform display

    private let baseBucketCount = 1200
    private let analyzer = WaveformAnalyzer()

    init(recording: Recording) {
        self.recording = recording
        self.previewDuration = recording.safeDuration
    }

    // MARK: - Waveform loading

    func loadWaveform() async {
        guard amplitudes.isEmpty else { return }
        guard let path = recording.storagePath else { return }
        let url = AudioImporter.recordingsDirectory.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        isLoadingWaveform = true
        waveformError = nil
        do {
            amplitudes = try await analyzer.analyze(url: url, bucketCount: baseBucketCount)
        } catch {
            waveformError = error
        }
        isLoadingWaveform = false
    }

    // MARK: - Marker management

    @discardableResult
    func addMarker(at seconds: Double, context: ModelContext) -> AyahMarker {
        let existing = sortedMarkers(in: context)
        let index = existing.count
        let marker = AyahMarker(recording: recording, position: seconds, index: index)
        context.insert(marker)
        try? context.save()
        return marker
    }

    func moveMarker(_ marker: AyahMarker, to seconds: Double) {
        marker.positionSeconds = seconds
    }

    func deleteMarker(_ marker: AyahMarker, context: ModelContext) {
        context.delete(marker)
        try? context.save()
    }

    func assignAyah(_ startRef: AyahRef?, endRef: AyahRef? = nil, to marker: AyahMarker, context: ModelContext) {
        marker.assignedSurah = startRef?.surah
        marker.assignedAyah  = startRef?.ayah
        marker.assignedEndSurah = endRef?.surah
        marker.assignedEndAyah  = endRef?.ayah
        marker.isConfirmed = true
        try? context.save()
    }

    /// Auto-assigns consecutive ayah refs starting from `startRef` to all markers in order.
    func autoAssign(startingFrom startRef: AyahRef,
                    markers: [AyahMarker],
                    context: ModelContext) {
        let metadata = QuranMetadataService.shared
        var current = startRef
        for marker in markers {
            marker.assignedSurah = current.surah
            marker.assignedAyah = current.ayah
            marker.isConfirmed = true
            current = metadata.ayah(after: current) ?? current
        }
        try? context.save()
    }

    // MARK: - Save segments

    /// Converts confirmed AyahMarkers → RecordingSegments and updates annotation status.
    func saveSegments(markers: [AyahMarker], context: ModelContext) throws {
        // 1. Delete existing segments for this recording
        for seg in recording.segments ?? [] {
            context.delete(seg)
        }

        // 2. Sort ALL markers by position
        let allSorted = markers.sorted { ($0.positionSeconds ?? 0) < ($1.positionSeconds ?? 0) }

        // 3. Build RecordingSegments via state machine.
        //    assignedSurah/assignedAyah       = start ayah at this marker (new segment opens here)
        //    assignedEndSurah/assignedEndAyah = end ayah at this marker   (previous segment closes here)
        var pendingStart: (time: Double, surah: Int, ayah: Int, reciterID: UUID?, riwayah: String?)? = nil
        var createdSegments = 0

        for marker in allSorted {
            let markerPos = marker.positionSeconds ?? 0
            let hasEnd = marker.assignedEndSurah != nil && marker.assignedEndAyah != nil
            let hasStart = marker.assignedSurah != nil && marker.assignedAyah != nil

            // Close the pending open segment when this marker has an end ayah
            if hasEnd, let start = pendingStart,
               let endSurah = marker.assignedEndSurah, let endAyah = marker.assignedEndAyah {
                let seg = RecordingSegment(
                    recording: recording,
                    startOffset: start.time,
                    endOffset: markerPos,
                    surah: start.surah,
                    ayah: start.ayah
                )
                seg.endSurahNumber = endSurah
                seg.endAyahNumber  = endAyah
                seg.isCrosssurahSegment = (endSurah != start.surah)
                seg.isManuallyAnnotated = true
                seg.confidenceScore = 1.0
                if let rid = start.reciterID {
                    let desc = FetchDescriptor<Reciter>(predicate: #Predicate { $0.id == rid })
                    seg.reciter = (try? context.fetch(desc))?.first
                }
                seg.riwayah = start.riwayah ?? Riwayah.hafs.rawValue
                context.insert(seg)
                createdSegments += 1
                pendingStart = nil
            } else if !hasEnd, hasStart, let start = pendingStart,
                      let newSurah = marker.assignedSurah, let newAyah = marker.assignedAyah {
                // A new start marker implicitly closes the previous segment.
                // Infer end ayah as the ayah just before the new start so multi-ayah segments
                // (e.g. 1:6→2:1 jump) are stored correctly and the queue skip works.
                let newStartRef = AyahRef(surah: newSurah, ayah: newAyah)
                let endRef = QuranMetadataService.shared.ayah(before: newStartRef)
                             ?? AyahRef(surah: start.surah, ayah: start.ayah)
                let seg = RecordingSegment(
                    recording: recording,
                    startOffset: start.time,
                    endOffset: markerPos,
                    surah: start.surah,
                    ayah: start.ayah
                )
                seg.endSurahNumber = endRef.surah
                seg.endAyahNumber  = endRef.ayah
                seg.isCrosssurahSegment = (endRef.surah != start.surah)
                seg.isManuallyAnnotated = true
                seg.confidenceScore = 1.0
                if let rid = start.reciterID {
                    let desc = FetchDescriptor<Reciter>(predicate: #Predicate { $0.id == rid })
                    seg.reciter = (try? context.fetch(desc))?.first
                }
                seg.riwayah = start.riwayah ?? Riwayah.hafs.rawValue
                context.insert(seg)
                createdSegments += 1
                pendingStart = nil
            }

            // Open a new segment if this marker has a start ayah
            if hasStart, let sS = marker.assignedSurah, let sA = marker.assignedAyah {
                pendingStart = (markerPos, sS, sA, marker.reciterID, marker.riwayah)
            }
        }

        // Handle last open segment (no closing end marker — extends to recording end)
        if let start = pendingStart {
            let seg = RecordingSegment(
                recording: recording,
                startOffset: start.time,
                endOffset: recording.safeDuration,
                surah: start.surah,
                ayah: start.ayah
            )
            seg.isManuallyAnnotated = true
            seg.confidenceScore = 1.0
            if let rid = start.reciterID {
                let desc = FetchDescriptor<Reciter>(predicate: #Predicate { $0.id == rid })
                seg.reciter = (try? context.fetch(desc))?.first
            }
            seg.riwayah = start.riwayah ?? Riwayah.hafs.rawValue
            context.insert(seg)
            createdSegments += 1
        }

        // 4. Update annotation status
        let totalMarkers = markers.count
        let confirmedCount = markers.filter { $0.isConfirmed == true }.count
        if totalMarkers == 0 || createdSegments == 0 {
            recording.annotationStatus = AnnotationStatus.unannotated.rawValue
        } else if confirmedCount == totalMarkers {
            recording.annotationStatus = AnnotationStatus.complete.rawValue
        } else {
            recording.annotationStatus = AnnotationStatus.partial.rawValue
        }

        // 5. Update coverage cache
        let surahNumbers = (recording.segments ?? []).compactMap { $0.surahNumber }
        recording.coversSurahStart = surahNumbers.min()
        recording.coversSurahEnd = surahNumbers.max()

        // 6. Delete AyahMarkers (editing session complete)
        for marker in markers {
            context.delete(marker)
        }

        try context.save()
    }

    // MARK: - Preview playback

    func togglePreview() {
        if isPreviewPlaying { stopPreview() }
        else { startPreview(from: previewPosition) }
    }

    func startPreview(from seconds: Double) {
        guard let path = recording.storagePath else { return }
        let url = AudioImporter.recordingsDirectory.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.currentTime = seconds
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            previewDuration = audioPlayer?.duration ?? recording.safeDuration
            previewPosition = seconds
            isPreviewPlaying = true

            positionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let player = self.audioPlayer else { return }
                    self.previewPosition = player.currentTime
                    let reachedEnd = self.segmentEndTime.map { player.currentTime >= $0 } ?? false
                    if !player.isPlaying || reachedEnd { self.stopPreview() }
                }
            }
        } catch {
            isPreviewPlaying = false
        }
    }

    func stopPreview() {
        audioPlayer?.stop()
        audioPlayer = nil
        positionUpdateTimer?.invalidate()
        positionUpdateTimer = nil
        isPreviewPlaying = false
        segmentEndTime = nil
    }

    /// Plays a specific time range and auto-stops at `end`.
    func playSegment(from start: Double, to end: Double) {
        stopPreview()
        segmentEndTime = end
        startPreview(from: start)
    }

    func seekPreview(to seconds: Double) {
        previewPosition = seconds
        audioPlayer?.currentTime = seconds
    }

    // MARK: - Reconstruct markers from saved segments

    /// Rebuilds AyahMarkers from existing RecordingSegments so the editor shows previous work.
    /// Each segment boundary becomes a marker; shared boundaries (consecutive segments) are merged
    /// into a single marker carrying both end and start ayah assignments.
    func reconstructMarkers(from segments: [RecordingSegment], context: ModelContext) {
        guard !segments.isEmpty else { return }
        let sorted = segments.sorted { ($0.startOffsetSeconds ?? 0) < ($1.startOffsetSeconds ?? 0) }

        var boundaries: [Double: (start: AyahRef?, end: AyahRef?)] = [:]
        var startReciterIDs: [Double: UUID] = [:]
        var startRiwayahs: [Double: String] = [:]
        for seg in sorted {
            let sPos = seg.startOffsetSeconds ?? 0
            let ePos = seg.endOffsetSeconds ?? recording.safeDuration
            let startRef = AyahRef(surah: seg.surahNumber ?? 1, ayah: seg.ayahNumber ?? 1)
            let endRef   = AyahRef(surah: seg.endSurahNumber ?? seg.surahNumber ?? 1,
                                   ayah: seg.endAyahNumber  ?? seg.ayahNumber  ?? 1)

            var s = boundaries[sPos] ?? (nil, nil); s.start = startRef; boundaries[sPos] = s
            if let rid = seg.reciter?.id { startReciterIDs[sPos] = rid }
            if let r = seg.riwayah { startRiwayahs[sPos] = r }
            var e = boundaries[ePos] ?? (nil, nil); e.end   = endRef;   boundaries[ePos] = e
        }

        for (i, (pos, refs)) in boundaries.sorted(by: { $0.key < $1.key }).enumerated() {
            let marker = AyahMarker(recording: recording, position: pos, index: i)
            marker.assignedSurah    = refs.start?.surah
            marker.assignedAyah     = refs.start?.ayah
            marker.assignedEndSurah = refs.end?.surah
            marker.assignedEndAyah  = refs.end?.ayah
            marker.isConfirmed      = refs.start != nil || refs.end != nil
            marker.reciterID        = startReciterIDs[pos]
            marker.riwayah          = startRiwayahs[pos]
            context.insert(marker)
        }
        try? context.save()
    }

    // MARK: - Auto marker type

    func autoMarkerType(for markers: [AyahMarker]) -> AyahMarker.MarkerType {
        guard let lastMarker = markers.last else { return .ayah }
        switch lastMarker.resolvedMarkerType {
        case .cropAfter: return .cropBefore
        case .cropBefore: return .ayah
        case .ayah: return .ayah
        }
    }

    // MARK: - Crop region computation

    /// Computes cropped regions from crop markers. Shared by WaveformView (rendering) and finalize.
    static func computeCropRegions(from markers: [AyahMarker], totalDuration: Double) -> [(start: Double, end: Double)] {
        let cropMarkers = markers
            .filter { $0.resolvedMarkerType != .ayah }
            .sorted { ($0.positionSeconds ?? 0) < ($1.positionSeconds ?? 0) }

        var regions: [(start: Double, end: Double)] = []
        var i = 0
        while i < cropMarkers.count {
            let m = cropMarkers[i]
            let pos = m.positionSeconds ?? 0
            if m.resolvedMarkerType == .cropBefore {
                regions.append((0, pos))
                i += 1
            } else if m.resolvedMarkerType == .cropAfter {
                if i + 1 < cropMarkers.count, cropMarkers[i + 1].resolvedMarkerType == .cropBefore {
                    let endPos = cropMarkers[i + 1].positionSeconds ?? totalDuration
                    regions.append((pos, endPos))
                    i += 2
                } else {
                    regions.append((pos, totalDuration))
                    i += 1
                }
            } else {
                i += 1
            }
        }
        return regions
    }


    // MARK: - Cut crop region (immediate)

    /// Cuts the first crop region from the audio file immediately.
    /// Backs up state for undo, remaps all marker positions, deletes the crop markers that defined the region.
    func cutCropRegion(markers: [AyahMarker], context: ModelContext) async throws {
        guard let path = recording.storagePath else { return }
        let url = AudioImporter.recordingsDirectory.appendingPathComponent(path)

        let totalDuration = recording.safeDuration
        let cropRegions = Self.computeCropRegions(from: markers, totalDuration: totalDuration)
        guard let region = cropRegions.first else { return }

        isProcessingEdit = true
        processingMessage = "Cropping selections…"
        defer { isProcessingEdit = false }

        stopPreview()

        // Save backup for undo
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo_\(UUID().uuidString).m4a")
        try FileManager.default.copyItem(at: url, to: backupURL)

        let allMarkers = sortedMarkers(in: context)
        let snapshot = CutSnapshot(
            backupURL: backupURL,
            duration: totalDuration,
            markerPositions: allMarkers.compactMap { m in
                guard let id = m.id, let pos = m.positionSeconds else { return nil }
                return (id, pos)
            }
        )
        undoStack.append(snapshot)

        // Clear redo stack — new action invalidates redo history
        for redo in redoStack { try? FileManager.default.removeItem(at: redo.backupURL) }
        redoStack.removeAll()

        // Delete the region from the audio file
        let newDuration = try await audioEditor.deleteRegion(
            fileURL: url, start: region.start, end: region.end
        )

        // Update storagePath if format changed (e.g., original was .caf)
        let newFilename = URL(fileURLWithPath: path).deletingPathExtension()
            .appendingPathExtension("m4a").lastPathComponent
        if recording.storagePath != newFilename {
            recording.storagePath = newFilename
            recording.fileFormat = "m4a"
        }

        // Update file size
        let newURL = AudioImporter.recordingsDirectory.appendingPathComponent(newFilename)
        let attrs = try? FileManager.default.attributesOfItem(atPath: newURL.path)
        recording.fileSizeBytes = attrs?[.size] as? Int

        let cutDuration = region.end - region.start

        // Remap all marker positions
        for marker in allMarkers {
            guard let pos = marker.positionSeconds else { continue }
            if pos >= region.start && pos <= region.end {
                // Marker inside cut region (including boundary crop markers) — delete it
                context.delete(marker)
            } else if pos >= region.end {
                // Marker after cut region — shift left
                marker.positionSeconds = pos - cutDuration
            }
            // Markers before the cut region stay unchanged
        }

        recording.durationSeconds = newDuration
        previewDuration = newDuration

        // Clamp preview position
        if previewPosition > newDuration { previewPosition = newDuration }
        else if previewPosition >= region.start { previewPosition = region.start }

        try? context.save()

        // Reload waveform
        amplitudes = []
        await loadWaveform()
    }

    /// Restores the audio file and marker positions from the last cut.
    func undoLastCut(markers: [AyahMarker], context: ModelContext) async throws {
        guard let snapshot = undoStack.popLast() else { return }
        guard let path = recording.storagePath else { return }

        isProcessingEdit = true
        defer { isProcessingEdit = false }

        stopPreview()

        // Save current state to redo stack before restoring
        let currentURL = AudioImporter.recordingsDirectory.appendingPathComponent(path)
        let redoBackupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("redo_\(UUID().uuidString).m4a")
        try FileManager.default.copyItem(at: currentURL, to: redoBackupURL)

        let allMarkers = sortedMarkers(in: context)
        let redoSnapshot = CutSnapshot(
            backupURL: redoBackupURL,
            duration: recording.safeDuration,
            markerPositions: allMarkers.compactMap { m in
                guard let id = m.id, let pos = m.positionSeconds else { return nil }
                return (id, pos)
            }
        )
        redoStack.append(redoSnapshot)

        // Restore the backed-up audio file
        try FileManager.default.removeItem(at: currentURL)
        let destURL = AudioImporter.recordingsDirectory
            .appendingPathComponent(URL(fileURLWithPath: path).deletingPathExtension()
                .appendingPathExtension("m4a").lastPathComponent)
        try FileManager.default.moveItem(at: snapshot.backupURL, to: destURL)

        let restoredFilename = destURL.lastPathComponent
        recording.storagePath = restoredFilename
        recording.fileFormat = "m4a"
        recording.durationSeconds = snapshot.duration
        previewDuration = snapshot.duration

        let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path)
        recording.fileSizeBytes = attrs?[.size] as? Int

        // Restore marker positions
        let currentMarkers = sortedMarkers(in: context)
        for (id, pos) in snapshot.markerPositions {
            if let marker = currentMarkers.first(where: { $0.id == id }) {
                marker.positionSeconds = pos
            }
        }

        if previewPosition > snapshot.duration { previewPosition = snapshot.duration }

        try? context.save()

        amplitudes = []
        await loadWaveform()
    }

    /// Re-applies the last undone cut.
    func redoLastCut(markers: [AyahMarker], context: ModelContext) async throws {
        guard let snapshot = redoStack.popLast() else { return }
        guard let path = recording.storagePath else { return }

        isProcessingEdit = true
        defer { isProcessingEdit = false }

        stopPreview()

        // Save current state to undo stack before re-applying
        let currentURL = AudioImporter.recordingsDirectory.appendingPathComponent(path)
        let undoBackupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo_\(UUID().uuidString).m4a")
        try FileManager.default.copyItem(at: currentURL, to: undoBackupURL)

        let allMarkers = sortedMarkers(in: context)
        let undoSnapshot = CutSnapshot(
            backupURL: undoBackupURL,
            duration: recording.safeDuration,
            markerPositions: allMarkers.compactMap { m in
                guard let id = m.id, let pos = m.positionSeconds else { return nil }
                return (id, pos)
            }
        )
        undoStack.append(undoSnapshot)

        // Restore the redo snapshot
        try FileManager.default.removeItem(at: currentURL)
        let destURL = AudioImporter.recordingsDirectory
            .appendingPathComponent(URL(fileURLWithPath: path).deletingPathExtension()
                .appendingPathExtension("m4a").lastPathComponent)
        try FileManager.default.moveItem(at: snapshot.backupURL, to: destURL)

        let restoredFilename = destURL.lastPathComponent
        recording.storagePath = restoredFilename
        recording.fileFormat = "m4a"
        recording.durationSeconds = snapshot.duration
        previewDuration = snapshot.duration

        let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path)
        recording.fileSizeBytes = attrs?[.size] as? Int

        let currentMarkers = sortedMarkers(in: context)
        for (id, pos) in snapshot.markerPositions {
            if let marker = currentMarkers.first(where: { $0.id == id }) {
                marker.positionSeconds = pos
            }
        }

        if previewPosition > snapshot.duration { previewPosition = snapshot.duration }

        try? context.save()

        amplitudes = []
        await loadWaveform()
    }

    /// Cleans up any undo/redo backup files.
    func cleanupUndoBackups() {
        for snapshot in undoStack { try? FileManager.default.removeItem(at: snapshot.backupURL) }
        for snapshot in redoStack { try? FileManager.default.removeItem(at: snapshot.backupURL) }
        undoStack.removeAll()
        redoStack.removeAll()
    }

    // MARK: - Finalize

    /// Keeps only annotated segment audio (excluding crop regions and unannotated gaps),
    /// concatenates them, remaps marker positions, saves segments, and updates the recording.
    func finalizeRecording(markers: [AyahMarker], context: ModelContext) async throws {
        guard let path = recording.storagePath else { return }
        let url = AudioImporter.recordingsDirectory.appendingPathComponent(path)

        let totalDuration = recording.safeDuration
        let ayahMarkers = markers.filter { $0.resolvedMarkerType == .ayah }
            .sorted { ($0.positionSeconds ?? 0) < ($1.positionSeconds ?? 0) }
        let cropRegions = Self.computeCropRegions(from: markers, totalDuration: totalDuration)

        // Build segment ranges using state-machine logic matching saveSegments.
        // A marker with a start ayah opens a segment; a marker with an end ayah
        // (or a new start ayah) closes the previous one. Gaps between segments
        // (e.g. rakaah breaks) are excluded from the kept ranges.
        var segmentRanges: [(start: Double, end: Double)] = []
        var pendingStart: Double? = nil

        for marker in ayahMarkers {
            let pos = marker.positionSeconds ?? 0
            let hasEnd = marker.assignedEndSurah != nil && marker.assignedEndAyah != nil
            let hasStart = marker.assignedSurah != nil && marker.assignedAyah != nil

            if hasEnd, let start = pendingStart {
                segmentRanges.append((start, pos))
                pendingStart = nil
            } else if !hasEnd, hasStart, let start = pendingStart {
                // New start implicitly closes the previous segment
                segmentRanges.append((start, pos))
                pendingStart = nil
            }

            if hasStart {
                pendingStart = pos
            }
        }

        // Last open segment extends to end of file
        if let start = pendingStart {
            segmentRanges.append((start, totalDuration))
        }

        // If no annotated segments, just save markers and return
        guard !segmentRanges.isEmpty else {
            try saveSegments(markers: ayahMarkers, context: context)
            return
        }

        // Subtract crop regions from segment ranges
        var keptRanges: [(start: Double, end: Double)] = []
        for seg in segmentRanges {
            var remaining = [seg]
            for crop in cropRegions.sorted(by: { $0.start < $1.start }) {
                var next: [(start: Double, end: Double)] = []
                for r in remaining {
                    if crop.end <= r.start || crop.start >= r.end {
                        // No overlap
                        next.append(r)
                    } else {
                        // Crop overlaps — split
                        if r.start < crop.start { next.append((r.start, crop.start)) }
                        if r.end > crop.end { next.append((crop.end, r.end)) }
                    }
                }
                remaining = next
            }
            keptRanges.append(contentsOf: remaining)
        }

        guard !keptRanges.isEmpty else { return }

        isProcessingEdit = true
        processingMessage = "Finalizing…"
        defer { isProcessingEdit = false }

        stopPreview()

        let (newDuration, mapping) = try await audioEditor.finalize(
            fileURL: url, segmentRanges: keptRanges
        )

        // Update storagePath if format changed
        let newFilename = URL(fileURLWithPath: path).deletingPathExtension()
            .appendingPathExtension("m4a").lastPathComponent
        if recording.storagePath != newFilename {
            recording.storagePath = newFilename
            recording.fileFormat = "m4a"
        }

        // Update file size
        let newURL = AudioImporter.recordingsDirectory.appendingPathComponent(newFilename)
        let attrs = try? FileManager.default.attributesOfItem(atPath: newURL.path)
        recording.fileSizeBytes = attrs?[.size] as? Int

        // Remap ayah marker positions; delete those that fall in removed regions
        for marker in ayahMarkers {
            guard let pos = marker.positionSeconds else { continue }
            if let map = mapping.first(where: { pos >= $0.oldStart && pos < $0.oldEnd }) {
                marker.positionSeconds = map.newStart + (pos - map.oldStart)
            } else {
                context.delete(marker)
            }
        }

        // Delete all crop markers
        for marker in markers.filter({ $0.resolvedMarkerType != .ayah }) {
            context.delete(marker)
        }

        recording.durationSeconds = newDuration
        previewDuration = newDuration

        // Force waveform reload
        amplitudes = []
        await loadWaveform()

        // Save segments from remaining ayah markers
        let remainingAyah = sortedMarkers(in: context).filter { $0.resolvedMarkerType == .ayah }
        if !remainingAyah.isEmpty {
            try saveSegments(markers: remainingAyah, context: context)
        } else {
            try context.save()
        }
    }

    // MARK: - Helpers

    private func sortedMarkers(in context: ModelContext) -> [AyahMarker] {
        let descriptor = FetchDescriptor<AyahMarker>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all
            .filter { $0.recording?.id == recording.id }
            .sorted { ($0.positionSeconds ?? 0) < ($1.positionSeconds ?? 0) }
    }
}
