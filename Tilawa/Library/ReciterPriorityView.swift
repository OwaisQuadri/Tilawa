import SwiftUI
import SwiftData

/// Drag-to-reorder list of all reciters in playback priority order.
/// "Auto" mode in PlaybackSetupSheet resolves reciters top-to-bottom through this list.
///
/// Contains two sections:
///   - "Default" — global reciter priority used for all ayaat without a segment override
///   - "Segments" — per-range overrides with their own reciter priority
struct ReciterPriorityView: View {

    @Environment(\.modelContext) private var context

    @Query private var allSettings: [PlaybackSettings]
    @Query private var allReciters: [Reciter]

    @State private var orderedEntries: [ReciterPriorityEntry] = []
    @State private var orderedSegments: [ReciterSegmentOverride] = []

    private var settings: PlaybackSettings? { allSettings.first }

    private let metadata = QuranMetadataService.shared

    var body: some View {
        List {
            defaultSection
            segmentsSection
        }
        .navigationTitle("Reciter Priority")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadOrder(); loadSegments() }
        .onChange(of: settings?.reciterPriority?.count) { _, _ in
            // Re-sync if entries are added/removed externally (e.g. manifest import)
            loadOrder()
        }
        .onChange(of: settings?.segmentOverrides?.count) { _, _ in loadSegments() }
    }

    // MARK: - Default section

    @ViewBuilder
    private var defaultSection: some View {
        Section {
            ForEach(orderedEntries, id: \.id) { entry in
                priorityRow(entry)
            }
            .onMove { from, to in
                orderedEntries.move(fromOffsets: from, toOffset: to)
                saveOrder()
            }
        } header: {
            Text("Default")
                .font(.headline)
                .textCase(nil)
        } footer: {
            Text("Hold and drag to reorder. Top reciter plays first in Auto mode.")
                .font(.caption)
        }
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Segments section

    @ViewBuilder
    private var segmentsSection: some View {
        Section {
            ForEach(orderedSegments, id: \.id) { override in
                NavigationLink {
                    SegmentReciterPriorityView(segmentOverride: override)
                        .onDisappear { loadSegments() }
                } label: {
                    segmentRow(override)
                }
            }
            .onDelete { indexSet in
                for i in indexSet { removeSegment(orderedSegments[i]) }
            }

            Button {
                addSegment()
            } label: {
                Label("Add Segment", systemImage: "plus.circle")
            }
        } header: {
            Text("Segments")
                .font(.headline)
                .textCase(nil)
        } footer: {
            Text("Segment overrides apply a different reciter order for specific ayah ranges. Swipe left to delete.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private func segmentRow(_ override: ReciterSegmentOverride) -> some View {
        let range = override.ayahRange
        let startName = metadata.surahName(range.start.surah)
        let endName   = metadata.surahName(range.end.surah)
        let label: String = {
            if range.start.surah == range.end.surah {
                return "\(startName) \(range.start.surah):\(range.start.ayah)–\(range.end.ayah)"
            }
            return "\(startName) \(range.start.surah):\(range.start.ayah) – \(endName) \(range.end.surah):\(range.end.ayah)"
        }()
        let count = (override.reciterPriority ?? []).filter { $0.isEnabled ?? true }.count

        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.body)
            Text(count == 0 ? "No reciters" : "\(count) reciter\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func priorityRow(_ entry: ReciterPriorityEntry) -> some View {
        let reciter = allReciters.first { $0.id == entry.reciterId }

        HStack(spacing: 12) {
            // Priority badge
            Text("#\((orderedEntries.firstIndex { $0.id == entry.id } ?? 0) + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(reciter?.safeName ?? "Unknown")
                    .font(.body)
                HStack(spacing: 6) {
                    Text(reciter?.riwayahSummaryLabel ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if reciter?.hasPersonalRecordings == true {
                        Label("Personal", systemImage: "waveform.badge.mic")
                            .font(.caption2)
                            .labelStyle(.iconOnly)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Default order management

    private func loadOrder() {
        guard let s = settings else { return }

        // Purge stale entries pointing to reciters that no longer exist
        let knownIds = Set(allReciters.compactMap { $0.id })
        let stale = (s.reciterPriority ?? []).filter {
            guard let id = $0.reciterId else { return true }
            return !knownIds.contains(id)
        }
        if !stale.isEmpty {
            stale.forEach { context.delete($0) }
            s.reciterPriority = (s.reciterPriority ?? []).filter { entry in
                guard let id = entry.reciterId else { return false }
                return knownIds.contains(id)
            }
            try? context.save()
        }

        orderedEntries = s.sortedReciterPriority

        // Auto-add any reciter with audio that isn't in the list yet (at the bottom)
        let listedIds = Set(orderedEntries.compactMap { $0.reciterId })
        let unlisted = allReciters.filter { r in
            guard let id = r.id else { return false }
            return !listedIds.contains(id) && (r.hasCDN || r.hasPersonalRecordings)
        }
        guard !unlisted.isEmpty else { return }
        let maxOrder = orderedEntries.compactMap { $0.order }.max() ?? -1
        for (i, reciter) in unlisted.enumerated() {
            let entry = ReciterPriorityEntry(order: maxOrder + 1 + i, reciterId: reciter.id!)
            context.insert(entry)
            s.reciterPriority = (s.reciterPriority ?? []) + [entry]
        }
        try? context.save()
        orderedEntries = s.sortedReciterPriority
    }

    private func saveOrder() {
        for (index, entry) in orderedEntries.enumerated() {
            entry.order = index
        }
        try? context.save()
    }

    // MARK: - Segment management

    private func loadSegments() {
        guard let s = settings else { return }
        orderedSegments = (s.segmentOverrides ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    private func addSegment() {
        guard let s = settings else { return }
        let maxOrder = (s.segmentOverrides ?? []).compactMap { $0.order }.max() ?? -1
        let override = ReciterSegmentOverride(
            startSurah: 1, startAyah: 1,
            endSurah: 1,   endAyah: 7,
            order: maxOrder + 1
        )
        context.insert(override)
        // Seed the segment's priority list from the current global priority
        let seedEntries: [SegmentReciterEntry] = s.sortedReciterPriority.enumerated().map { index, entry in
            let segEntry = SegmentReciterEntry(order: index, reciterId: entry.reciterId ?? UUID())
            segEntry.isEnabled = entry.isEnabled
            return segEntry
        }
        seedEntries.forEach { context.insert($0) }
        override.reciterPriority = seedEntries
        s.segmentOverrides = (s.segmentOverrides ?? []) + [override]
        try? context.save()
        loadSegments()
    }

    private func removeSegment(_ override: ReciterSegmentOverride) {
        guard let s = settings else { return }
        orderedSegments.removeAll { $0.id == override.id }
        s.segmentOverrides = (s.segmentOverrides ?? []).filter { $0.id != override.id }
        context.delete(override)
        try? context.save()
    }
}
