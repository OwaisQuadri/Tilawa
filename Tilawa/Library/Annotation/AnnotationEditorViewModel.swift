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

    // MARK: - Auto-detect

    var silenceThreshold: Float = 0.04
    var isRunningAutoDetect = false

    // MARK: - Waveform display

    /// Bucket count used for waveform analysis. Enough detail for a scrollable view.
    private let bucketCount = 1200
    private let analyzer = WaveformAnalyzer()
    private let detector = SilenceDetector()

    init(recording: Recording) {
        self.recording = recording
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
            amplitudes = try await analyzer.analyze(url: url, bucketCount: bucketCount)
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

    // MARK: - Auto-detect silences

    func runAutoDetect(markers: [AyahMarker], context: ModelContext) {
        guard !amplitudes.isEmpty else { return }
        isRunningAutoDetect = true

        var detector = SilenceDetector()
        detector.silenceThreshold = silenceThreshold

        let boundaries = detector.detectBoundaries(in: amplitudes)
        let duration = recording.safeDuration

        // Remove existing unconfirmed markers to avoid duplicates
        for marker in markers where marker.isConfirmed == false {
            context.delete(marker)
        }

        let confirmedCount = markers.filter { $0.isConfirmed == true }.count
        for (i, bucket) in boundaries.enumerated() {
            let seconds = detector.seconds(for: bucket,
                                            totalBuckets: amplitudes.count,
                                            duration: duration)
            let marker = AyahMarker(recording: recording,
                                    position: seconds,
                                    index: confirmedCount + i)
            context.insert(marker)
        }
        try? context.save()
        isRunningAutoDetect = false
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
        var pendingStart: (time: Double, surah: Int, ayah: Int)? = nil
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
                context.insert(seg)
                createdSegments += 1
                pendingStart = nil
            }

            // Open a new segment if this marker has a start ayah
            if hasStart, let sS = marker.assignedSurah, let sA = marker.assignedAyah {
                pendingStart = (markerPos, sS, sA)
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
        for seg in sorted {
            let sPos = seg.startOffsetSeconds ?? 0
            let ePos = seg.endOffsetSeconds ?? recording.safeDuration
            let startRef = AyahRef(surah: seg.surahNumber ?? 1, ayah: seg.ayahNumber ?? 1)
            let endRef   = AyahRef(surah: seg.endSurahNumber ?? seg.surahNumber ?? 1,
                                   ayah: seg.endAyahNumber  ?? seg.ayahNumber  ?? 1)

            var s = boundaries[sPos] ?? (nil, nil); s.start = startRef; boundaries[sPos] = s
            var e = boundaries[ePos] ?? (nil, nil); e.end   = endRef;   boundaries[ePos] = e
        }

        for (i, (pos, refs)) in boundaries.sorted(by: { $0.key < $1.key }).enumerated() {
            let marker = AyahMarker(recording: recording, position: pos, index: i)
            marker.assignedSurah    = refs.start?.surah
            marker.assignedAyah     = refs.start?.ayah
            marker.assignedEndSurah = refs.end?.surah
            marker.assignedEndAyah  = refs.end?.ayah
            marker.isConfirmed      = refs.start != nil || refs.end != nil
            context.insert(marker)
        }
        try? context.save()
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
