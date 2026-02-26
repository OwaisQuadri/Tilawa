import SwiftUI
import SwiftData

/// Drag-to-reorder list of all segments competing for the same ayah (same reciter, same surah:ayah).
/// Allows the user to control which recording is preferred during playback.
struct SegmentPriorityView: View {

    let surah: Int
    let ayah: Int
    let reciterId: UUID

    @Environment(\.modelContext) private var context

    @Query private var allSegments: [RecordingSegment]

    @State private var orderedSegments: [RecordingSegment] = []
    @State private var isEditing = false

    init(surah: Int, ayah: Int, reciterId: UUID) {
        self.surah = surah
        self.ayah = ayah
        self.reciterId = reciterId
        _allSegments = Query(
            filter: #Predicate<RecordingSegment> {
                $0.surahNumber == surah && $0.ayahNumber == ayah
            },
            sort: \RecordingSegment.userSortOrder
        )
    }

    private var relevantSegments: [RecordingSegment] {
        allSegments.filter { $0.recording?.reciter?.id == reciterId }
    }

    private let metadata = QuranMetadataService.shared

    var body: some View {
        List {
            Section {
                ForEach(orderedSegments, id: \.id) { segment in
                    segmentRow(segment)
                }
                .onMove { from, to in
                    orderedSegments.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text("Drag to set priority. Top recording plays first.")
                    .textCase(nil)
                    .font(.caption)
            } footer: {
                Text("Default: newest recording wins. Tap Reset to restore.")
                    .font(.caption)
            }
        }
        .navigationTitle("\(metadata.surahName(surah)) \(surah):\(ayah)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button("Reset to Default", role: .destructive) { resetOrder() }
                    Spacer()
                    Button("Save") { saveOrder() }
                        .fontWeight(.semibold)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .onAppear { loadOrder() }
        .onChange(of: relevantSegments.count) { _, _ in loadOrder() }
    }

    @ViewBuilder
    private func segmentRow(_ segment: RecordingSegment) -> some View {
        let recording = segment.recording
        VStack(alignment: .leading, spacing: 4) {
            Text(recording?.safeTitle ?? "Unknown Recording")
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 8) {
                if let date = recording?.importedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let segStart = segment.startOffsetSeconds ?? 0
                let segEnd = segment.endOffsetSeconds ?? 0
                Text("\(timeString(segStart)) – \(timeString(segEnd))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                if segment.isManuallyAnnotated == true {
                    Label("Manual", systemImage: "hand.point.up")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                } else if let score = segment.confidenceScore {
                    Text(String(format: "%.0f%%", score * 100))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if segment.userSortOrder == nil {
                Text("Default (newest first)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(.vertical, 2)
    }

    private func loadOrder() {
        // If user sort orders are set, use them; otherwise sort by importedAt newest first
        let segs = relevantSegments
        let hasExplicitOrder = segs.contains { $0.userSortOrder != nil }
        if hasExplicitOrder {
            orderedSegments = segs.sorted {
                let lo = $0.userSortOrder ?? Int.max
                let ro = $1.userSortOrder ?? Int.max
                if lo != ro { return lo < ro }
                return ($0.recording?.importedAt ?? .distantPast) >
                       ($1.recording?.importedAt ?? .distantPast)
            }
        } else {
            orderedSegments = segs.sorted {
                ($0.recording?.importedAt ?? .distantPast) >
                ($1.recording?.importedAt ?? .distantPast)
            }
        }
    }

    private func saveOrder() {
        for (index, segment) in orderedSegments.enumerated() {
            segment.userSortOrder = index
        }
        try? context.save()
    }

    private func resetOrder() {
        for segment in orderedSegments {
            segment.userSortOrder = nil
        }
        try? context.save()
        loadOrder()
    }

    private func timeString(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
