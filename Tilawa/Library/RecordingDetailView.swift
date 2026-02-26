import SwiftUI
import SwiftData

/// Detail view for a single Recording showing all its segments and conflict badges.
struct RecordingDetailView: View {

    let recording: Recording

    @Environment(\.modelContext) private var context

    @State private var showAnnotationEditor = false

    @Query private var allSegments: [RecordingSegment]

    private let metadata = QuranMetadataService.shared

    init(recording: Recording) {
        self.recording = recording
        // Fetch all segments to find conflicts — we filter in-memory
        _allSegments = Query(sort: \RecordingSegment.surahNumber)
    }

    private var recordingSegments: [RecordingSegment] {
        recording.sortedSegments
    }

    var body: some View {
        List {
            // Recording metadata
            Section("Info") {
                LabeledContent("Duration", value: durationLabel)
                LabeledContent("Format", value: (recording.fileFormat ?? "—").uppercased())
                if let date = recording.importedAt {
                    LabeledContent("Imported", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                NavigationLink {
                    ReciterPickerView(recording: recording)
                } label: {
                    LabeledContent("Reciter") {
                        Text(recording.reciter?.safeName ?? "None")
                            .foregroundStyle(recording.reciter == nil ? .tertiary : .secondary)
                    }
                }
                Picker("Riwayah", selection: Binding(
                    get: { recording.safeRiwayah },
                    set: { recording.riwayah = $0.rawValue; try? context.save() }
                )) {
                    ForEach(Riwayah.allCases, id: \.self) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                LabeledContent("Status") {
                    statusBadge
                }
            }

            // Annotation action
            Section {
                Button {
                    showAnnotationEditor = true
                } label: {
                    Label("Open Annotation Editor", systemImage: "waveform.path")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Segments
            if !recordingSegments.isEmpty {
                Section("Segments (\(recordingSegments.count))") {
                    ForEach(recordingSegments, id: \.id) { segment in
                        segmentRow(segment)
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "No Segments",
                        systemImage: "tag.slash",
                        description: Text("Open the annotation editor to tag this recording.")
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(recording.safeTitle)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showAnnotationEditor) {
            AnnotationEditorView(recording: recording)
        }
    }

    @ViewBuilder
    private func segmentRow(_ segment: RecordingSegment) -> some View {
        let surah = segment.surahNumber ?? 1
        let ayah = segment.ayahNumber ?? 1
        let conflicts = conflictCount(for: segment)
        let reciterId = recording.reciter?.id

        NavigationLink {
            if let rid = reciterId {
                SegmentPriorityView(surah: surah, ayah: ayah, reciterId: rid)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(metadata.surahName(surah)) \(surah):\(ayah)")
                        .font(.subheadline)
                    Text("\(timeString(segment.startOffsetSeconds ?? 0)) – \(timeString(segment.endOffsetSeconds ?? 0))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if conflicts > 0 {
                    Label("\(conflicts) competing", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .disabled(reciterId == nil)
    }

    /// Returns the number of other segments (from different recordings) covering the same ayah.
    private func conflictCount(for segment: RecordingSegment) -> Int {
        guard let reciterId = recording.reciter?.id,
              let surah = segment.surahNumber,
              let ayah = segment.ayahNumber else { return 0 }

        return allSegments.filter {
            $0.surahNumber == surah &&
            $0.ayahNumber == ayah &&
            $0.recording?.reciter?.id == reciterId &&
            $0.recording?.id != recording.id
        }.count
    }

    private var durationLabel: String {
        let secs = Int(recording.safeDuration)
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch recording.annotationStatusEnum {
        case .unannotated:
            Label("Untagged", systemImage: "tag.slash").foregroundStyle(.orange)
        case .partial:
            Label("Partial", systemImage: "tag").foregroundStyle(.yellow)
        case .complete:
            Label("Tagged", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
