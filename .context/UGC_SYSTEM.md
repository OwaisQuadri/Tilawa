# Tilawa — UGC System Design

**Version:** 1.0

---

## 1. Overview

The UGC system allows users to build a personal library of Quran recitation recordings — from live prayers, halaqas, or personal sessions — and use them as first-class audio sources in the playback engine. The system consists of:

1. **Import** — bring audio from Files, Voice Memos, or direct recording
2. **Storage** — iCloud Drive via ubiquity container for durability and sync
3. **Annotation** — waveform editor to mark ayah boundaries with minimal friction
4. **Resolution** — querying annotations to serve correct audio during playback

---

## 2. Import Flow

```
User taps "+" in RecordingLibraryView
        │
        ▼
ActionSheet:
    [ Import from Files ]
    [ Import from Voice Memos ]
    [ Record Now ]
        │
        ├─── Files ──────────────────────────────────────────────────────▶ FilesPicker
        │                                                                    (UIDocumentPickerVC)
        │                                                                    accepted: .audio
        │
        ├─── Voice Memos ────────────────────────────────────────────────▶ VoiceMemosPicker
        │                                                                    (MPMediaPickerController)
        │
        └─── Record Now ─────────────────────────────────────────────────▶ InAppRecorder
                                                                            (AVAudioRecorder)
        │
        ▼ (all paths converge here)
RecordingImporter.importFile(url: URL) async throws -> Recording
        │
        ├── Copy file to iCloud ubiquity container
        │       FileManager.default
        │           .url(forUbiquityContainerIdentifier: nil)?
        │           .appendingPathComponent("Recordings/\(uuid).\(ext)")
        │
        ├── Create Recording @Model, insert into modelContext
        ├── Extract metadata: AVURLAsset → duration, format, file date
        │
        ▼
Auto-navigate to AnnotationEditorView for the new recording
```

### iCloud Storage Path Convention
```
iCloud Drive / Tilawa / Recordings / {uuid}.{ext}
```
The `Recording.storagePath` stores the relative path: `"Recordings/{uuid}.{ext}"`.
Full URL reconstruction: `ubiquityContainerURL.appendingPathComponent(storagePath)`

---

## 3. Waveform Analysis

```swift
// UGC/WaveformAnalyzer.swift
actor WaveformAnalyzer {

    // Returns a normalized amplitude array suitable for rendering.
    // targetSamples controls display resolution (1000 = good for most screen widths).
    func analyze(url: URL, targetSamples: Int = 1000) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformError.noAudioTrack
        }

        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(trackOutput)
        reader.startReading()

        var rawSamples: [Int16] = []
        while reader.status == .reading,
              let buffer = trackOutput.copyNextSampleBuffer(),
              let blockBuffer = CMSampleBufferGetDataBuffer(buffer) {
            var lengthAtOffset = 0
            var totalLength = 0
            var rawData: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                        lengthAtOffsetOut: &lengthAtOffset,
                                        totalLengthOut: &totalLength,
                                        dataPointerOut: &rawData)
            if let rawData {
                let sampleCount = totalLength / MemoryLayout<Int16>.size
                let samples = UnsafeBufferPointer<Int16>(
                    start: rawData.withMemoryRebound(to: Int16.self, capacity: sampleCount) { $0 },
                    count: sampleCount
                )
                rawSamples.append(contentsOf: samples)
            }
        }

        // Downsample to targetSamples using RMS per chunk
        let chunkSize = max(1, rawSamples.count / targetSamples)
        var amplitudes = [Float](repeating: 0, count: targetSamples)
        for i in 0..<targetSamples {
            let start = i * chunkSize
            let end = min(start + chunkSize, rawSamples.count)
            guard start < rawSamples.count else { break }
            let chunk = rawSamples[start..<end].map { Float($0) / Float(Int16.max) }
            var rms: Float = 0
            vDSP_rmsqv(chunk, 1, &rms, vDSP_Length(chunk.count))
            amplitudes[i] = rms
        }

        // Normalize to 0.0–1.0
        let peak = amplitudes.max() ?? 1.0
        if peak > 0 {
            vDSP_vsdiv(amplitudes, 1, [peak], &amplitudes, 1, vDSP_Length(amplitudes.count))
        }

        return amplitudes
    }
}
```

---

## 4. Silence Detection

```swift
// UGC/SilenceDetector.swift
struct SilenceRegion {
    let startSeconds: Double
    let endSeconds: Double
    var midpointSeconds: Double { (startSeconds + endSeconds) / 2.0 }
    var durationMs: Int { Int((endSeconds - startSeconds) * 1000) }
}

struct SilenceDetector {

    // Detects regions of silence from a pre-computed amplitude array.
    // amplitudes: normalized [Float] from WaveformAnalyzer
    // duration: total recording duration in seconds
    // silenceThreshold: RMS below this = silence (default 0.02 = ~-34 dBFS)
    // minSilenceDurationMs: ignore silences shorter than this
    func detect(amplitudes: [Float],
                duration: Double,
                silenceThreshold: Float = 0.02,
                minSilenceDurationMs: Int = 400) -> [SilenceRegion] {

        let samplesPerSecond = Double(amplitudes.count) / duration
        var regions: [SilenceRegion] = []
        var silenceStart: Double? = nil

        for (i, amp) in amplitudes.enumerated() {
            let time = Double(i) / samplesPerSecond

            if amp < silenceThreshold {
                if silenceStart == nil { silenceStart = time }
            } else {
                if let start = silenceStart {
                    let durationMs = Int((time - start) * 1000)
                    if durationMs >= minSilenceDurationMs {
                        regions.append(SilenceRegion(startSeconds: start, endSeconds: time))
                    }
                    silenceStart = nil
                }
            }
        }

        // Handle trailing silence
        if let start = silenceStart {
            let durationMs = Int((duration - start) * 1000)
            if durationMs >= minSilenceDurationMs {
                regions.append(SilenceRegion(startSeconds: start, endSeconds: duration))
            }
        }

        // Merge regions within 100ms of each other
        return merge(regions: regions, gapThresholdMs: 100)
    }

    private func merge(regions: [SilenceRegion], gapThresholdMs: Int) -> [SilenceRegion] {
        guard !regions.isEmpty else { return [] }
        var merged: [SilenceRegion] = [regions[0]]
        for region in regions.dropFirst() {
            let gapMs = Int((region.startSeconds - merged.last!.endSeconds) * 1000)
            if gapMs <= gapThresholdMs {
                merged[merged.count - 1] = SilenceRegion(
                    startSeconds: merged.last!.startSeconds,
                    endSeconds: region.endSeconds
                )
            } else {
                merged.append(region)
            }
        }
        return merged
    }
}
```

---

## 5. Annotation Editor UX

### Screen Layout

```
┌────────────────────────────────────────────────────────────────┐
│  [←] Sheikh Recording - Jumu'ah 2024-01-05         [Save]     │
├────────────────────────────────────────────────────────────────┤
│  ▶  00:04:23 / 00:45:12   ────────────────────── [Auto-detect] │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  [Waveform Canvas — horizontally scrollable]                   │
│   ▓▓▓▓▓▓▓▓▓▓▓▒▒░░▓▓▓▓▓▓▓▒▒░░░▓▓▓▓▓▓▓▒▒░░▓▓▓▓▓▓▓▓              │
│              │         │         │                             │
│              ◆         ◆         ◆  ← marker handles           │
│           [1:2]    [unassigned]  [1:3]                         │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│  Segments (3 of 7 assigned)                                    │
│  ────────────────────────────────────────────────              │
│  ▶  0:00 – 0:04  [Al-Fatiha 1:1] ✓                            │
│  ▶  0:04 – 0:08  [Al-Fatiha 1:2] ✓                            │
│  ▶  0:08 – 0:12  [unassigned]    tap to assign ›               │
│  ...                                                           │
└────────────────────────────────────────────────────────────────┘
```

### Interaction Details

**Waveform tap** → add a new unconfirmed marker at that time position
**Marker drag** → reposition marker; snaps to nearest silence trough within ±200ms
**Marker long-press** → delete marker (with confirmation)
**Segment tap (in list)** → opens `SegmentAssignmentView` for that segment; auto-plays the segment in a loop

**Auto-detect button:**
1. Runs `SilenceDetector.detect()` on the waveform data (already computed)
2. Places suggested markers (rendered in orange/amber, distinct from confirmed blue markers)
3. Shows banner: "Found 23 boundaries. Review and confirm."

**Save button:**
- Validates: all segments must be either assigned or explicitly marked as "skip/unused"
- Calls `AnnotationEngine.saveAnnotations(recording:markers:modelContext:)`
- Updates `Recording.annotationStatus` to `"complete"` or `"partial"` based on coverage
- Recalculates `Recording.coversSurahStart/End`

---

## 6. AnnotationViewModel

```swift
// ViewModels/AnnotationViewModel.swift
@Observable
final class AnnotationViewModel {

    // MARK: - State
    var amplitudes: [Float] = []
    var isLoadingWaveform: Bool = false
    var markers: [AyahMarker] = []          // sorted by positionSeconds
    var selectedMarkerIndex: Int? = nil
    var playheadPosition: Double = 0.0      // 0.0–1.0 (fraction of duration)
    var isPlayingSegment: Bool = false
    var segmentPlaybackStart: Double = 0.0  // seconds
    var segmentPlaybackEnd: Double = 0.0

    // MARK: - Recording
    let recording: Recording
    private let waveformAnalyzer = WaveformAnalyzer()
    private let silenceDetector = SilenceDetector()

    init(recording: Recording) {
        self.recording = recording
        self.markers = recording.markers ?? []
    }

    // MARK: - Waveform
    func loadWaveform() async {
        isLoadingWaveform = true
        defer { isLoadingWaveform = false }
        guard let url = recordingURL else { return }
        amplitudes = (try? await waveformAnalyzer.analyze(url: url)) ?? []
    }

    // MARK: - Markers
    func addMarker(at seconds: Double) {
        let index = markers.count
        let marker = AyahMarker(recording: recording, position: seconds, index: index)
        markers.append(marker)
        markers.sort { ($0.positionSeconds ?? 0) < ($1.positionSeconds ?? 0) }
        renumberMarkers()
    }

    func moveMarker(id: UUID, to seconds: Double) {
        guard let idx = markers.firstIndex(where: { $0.id == id }) else { return }
        markers[idx].positionSeconds = seconds
        markers.sort { ($0.positionSeconds ?? 0) < ($1.positionSeconds ?? 0) }
        renumberMarkers()
    }

    func deleteMarker(id: UUID) {
        markers.removeAll { $0.id == id }
        renumberMarkers()
    }

    func assignAyah(markerId: UUID, surah: Int, ayah: Int) {
        guard let idx = markers.firstIndex(where: { $0.id == markerId }) else { return }
        markers[idx].assignedSurah = surah
        markers[idx].assignedAyah = ayah
        markers[idx].isConfirmed = true
    }

    // MARK: - Auto-detect
    func autoDetectBoundaries() {
        let duration = recording.safeDuration
        let regions = silenceDetector.detect(amplitudes: amplitudes, duration: duration)
        let newMarkers = regions.enumerated().map { i, region in
            AyahMarker(recording: recording, position: region.midpointSeconds, index: i)
        }
        // Only add if not already covered by existing confirmed markers
        for marker in newMarkers {
            let nearbyConfirmed = markers.contains {
                $0.isConfirmed == true &&
                abs(($0.positionSeconds ?? 0) - (marker.positionSeconds ?? 0)) < 0.5
            }
            if !nearbyConfirmed {
                markers.append(marker)
            }
        }
        markers.sort { ($0.positionSeconds ?? 0) < ($1.positionSeconds ?? 0) }
        renumberMarkers()
    }

    // MARK: - Save
    func saveAnnotations(modelContext: ModelContext) {
        AnnotationEngine.shared.saveAnnotations(
            recording: recording,
            markers: markers,
            modelContext: modelContext
        )
    }

    private func renumberMarkers() {
        for i in markers.indices { markers[i].markerIndex = i }
    }

    private var recordingURL: URL? {
        guard let path = recording.storagePath,
              let base = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return base.appendingPathComponent(path)
    }
}
```

---

## 7. Segment Assignment View

```swift
// Views/UGC/SegmentAssignmentView.swift
// Presented as a sheet when user taps a segment in the annotation editor

struct SegmentAssignmentView: View {
    let segment: SegmentForAssignment   // start/end times + index
    @Binding var assignedSurah: Int?
    @Binding var assignedAyah: Int?
    @Binding var isCrosssurah: Bool
    @Binding var endSurah: Int?
    @Binding var endAyah: Int?
    @Binding var crossSurahJoinOffset: Double  // time within segment

    @Environment(AnnotationViewModel.self) private var annotationVM

    var body: some View {
        NavigationStack {
            Form {
                // Auto-plays the segment in a loop for identification
                Section("Listen") {
                    SegmentAudioPlayerView(
                        startSeconds: segment.startSeconds,
                        endSeconds: segment.endSeconds,
                        recordingURL: annotationVM.recordingURL
                    )
                }

                Section("Assign Ayah") {
                    SurahPickerView(selection: $assignedSurah)
                    AyahPickerView(surah: assignedSurah, selection: $assignedAyah)
                }

                // Cross-surah toggle (e.g., Anfal end → Tawbah start)
                Section {
                    Toggle("This segment spans a surah boundary", isOn: $isCrosssurah)

                    if isCrosssurah {
                        Text("Where does the surah change?")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Mini waveform scoped to just this segment
                        SegmentWaveformScrubber(
                            recordingURL: annotationVM.recordingURL,
                            segmentStart: segment.startSeconds,
                            segmentEnd: segment.endSeconds,
                            position: $crossSurahJoinOffset
                        )

                        Text("End surah:")
                        SurahPickerView(selection: $endSurah)
                        AyahPickerView(surah: endSurah, selection: $endAyah)
                    }
                } header: {
                    Text("Advanced")
                }
            }
            .navigationTitle("Assign Segment \(segment.index + 1)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { /* dismiss + save */ }
                        .disabled(assignedSurah == nil || assignedAyah == nil)
                }
            }
        }
    }
}
```

---

## 8. Annotation Engine (Persistence)

```swift
// UGC/AnnotationEngine.swift
final class AnnotationEngine {
    static let shared = AnnotationEngine()

    func saveAnnotations(recording: Recording,
                         markers: [AyahMarker],
                         modelContext: ModelContext) {

        // Delete existing unconfirmed segments for this recording
        recording.segments?.removeAll { !($0.isManuallyAnnotated ?? false) }

        // Sort markers by time
        let sorted = markers.sorted { ($0.positionSeconds ?? 0) < ($1.positionSeconds ?? 0) }

        // Each pair of adjacent markers (or file-start/end) defines a segment
        var segmentBoundaries: [(start: Double, end: Double)] = []
        let starts = [0.0] + sorted.map { $0.positionSeconds ?? 0 }
        let ends = sorted.map { $0.positionSeconds ?? 0 } + [recording.safeDuration]
        for (start, end) in zip(starts, ends) {
            segmentBoundaries.append((start, end))
        }

        // Create RecordingSegment for each confirmed marker interval
        for (i, bounds) in segmentBoundaries.enumerated() {
            guard i < sorted.count else { break }
            let marker = sorted[i]
            guard let surah = marker.assignedSurah,
                  let ayah = marker.assignedAyah else { continue }

            let segment = RecordingSegment(
                recording: recording,
                startOffset: bounds.start,
                endOffset: bounds.end,
                surah: surah,
                ayah: ayah
            )
            segment.isManuallyAnnotated = marker.isConfirmed ?? false

            // Handle cross-surah
            // (cross-surah info stored on AyahMarker in extended form — add fields as needed)

            modelContext.insert(segment)
            recording.segments?.append(segment)
        }

        // Update recording coverage cache
        let allSurahs = (recording.segments ?? []).compactMap { $0.surahNumber }
        recording.coversSurahStart = allSurahs.min()
        recording.coversSurahEnd = allSurahs.max()

        let allConfirmed = (recording.markers ?? []).allSatisfy { $0.isConfirmed == true }
        recording.annotationStatus = allConfirmed ? "complete" : "partial"

        // Clear ephemeral markers now that segments are saved
        recording.markers = []
    }
}
```

---

## 9. RecordingLibraryService (SwiftData Queries)

```swift
// UGC/RecordingLibraryService.swift
@MainActor
final class RecordingLibraryService {

    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // Find all segments for a given ayah reference, optionally scoped to a specific reciter.
    // ReciterResolver calls this with a reciter to check personal recordings per-reciter.
    func segments(for ref: AyahRef, reciter: Reciter? = nil) -> [RecordingSegment] {
        let surah = ref.surah
        let ayah = ref.ayah
        let reciterId = reciter?.id

        let descriptor = FetchDescriptor<RecordingSegment>(
            predicate: #Predicate<RecordingSegment> { segment in
                // Ayah match: primary OR cross-surah end
                let ayahMatch = (segment.surahNumber == surah && segment.ayahNumber == ayah)
                    || (segment.endSurahNumber == surah && segment.endAyahNumber == ayah
                        && segment.isCrosssurahSegment == true)
                // Reciter match: if reciterId is non-nil, filter to that reciter's recordings
                let reciterMatch = reciterId == nil
                    || segment.recording?.reciter?.id == reciterId
                return ayahMatch && reciterMatch
            }
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // Returns list of AyahRefs with NO audio from any personal recording
    // Used for pre-flight coverage check
    func missingAyaat(in range: AyahRange, metadata: QuranMetadataService) -> [AyahRef] {
        var cursor = range.start
        var missing: [AyahRef] = []
        while cursor <= range.end {
            if segments(for: cursor).isEmpty { missing.append(cursor) }
            guard let next = metadata.ayah(after: cursor) else { break }
            cursor = next
        }
        return missing
    }
}
```

---

## 10. iCloud File Availability

```swift
// UGC/RecordingImporter.swift
enum FileAvailability {
    case available
    case cloudOnly           // exists in iCloud but not downloaded to device
    case downloading(Double) // progress 0.0–1.0
    case unavailable
}

func availability(of recording: Recording) -> FileAvailability {
    guard let path = recording.storagePath,
          let base = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
        return .unavailable
    }
    let url = base.appendingPathComponent(path)

    guard let values = try? url.resourceValues(forKeys: [
        .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemDownloadingErrorKey
    ]) else { return .unavailable }

    switch values.ubiquitousItemDownloadingStatus {
    case .current:
        return .available
    case .downloaded:
        return .available
    case .notDownloaded:
        if values.ubiquitousItemIsDownloading == true {
            return .downloading(0.5)  // progress metadata requires NSMetadataQuery for precision
        }
        return .cloudOnly
    default:
        return .unavailable
    }
}

// Trigger download for a cloudOnly file
func triggerDownload(recording: Recording) {
    guard let path = recording.storagePath,
          let base = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return }
    let url = base.appendingPathComponent(path)
    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
}
```
