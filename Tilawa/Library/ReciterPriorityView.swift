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

    // Reciters that have no priority entry yet (only show reciters with actual audio sources)
    private var unlistedReciters: [Reciter] {
        let listedIds = Set(orderedEntries.compactMap { $0.reciterId })
        return allReciters.filter { r in
            guard let id = r.id else { return false }
            return !listedIds.contains(id) && (r.hasCDN || r.hasPersonalRecordings)
        }.sorted { $0.safeName < $1.safeName }
    }

    private let metadata = QuranMetadataService.shared

    var body: some View {
        List {
            defaultSection
            segmentsSection

            if !unlistedReciters.isEmpty {
                Section("Not in priority list") {
                    ForEach(unlistedReciters, id: \.id) { reciter in
                        Button {
                            addToPriority(reciter)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reciter.safeName)
                                        .foregroundStyle(.primary)
                                    Text(reciter.safeRiwayah.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                }
            }
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
            .onDelete { indexSet in
                for i in indexSet {
                    removeEntry(orderedEntries[i])
                }
            }
        } header: {
            Text("Default")
                .font(.headline)
                .textCase(nil)
        } footer: {
            Text("Hold and drag to reorder. Top reciter plays first in Auto mode. Swipe left to remove a reciter from the Auto list. Removed reciters still exist in your library.")
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
                    Text(reciter?.safeRiwayah.displayName ?? "")
                        .font(.caption)
                    if let style = reciter?.style, !style.isEmpty {
                        Text("· \(style.capitalized)")
                            .font(.caption)
                    }
                    if reciter?.hasPersonalRecordings == true {
                        Label("Personal", systemImage: "waveform.badge.mic")
                            .font(.caption2)
                            .labelStyle(.iconOnly)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Enable/disable toggle
            Toggle("", isOn: enabledBinding(entry))
                .labelsHidden()
                .controlSize(.small)
        }
        .opacity(entry.isEnabled == false ? 0.4 : 1.0)
    }

    // MARK: - Default order management

    private func loadOrder() {
        guard let s = settings else { return }
        orderedEntries = s.sortedReciterPriority
    }

    private func saveOrder() {
        for (index, entry) in orderedEntries.enumerated() {
            entry.order = index
        }
        try? context.save()
    }

    private func addToPriority(_ reciter: Reciter) {
        guard let reciterId = reciter.id, let s = settings else { return }
        let maxOrder = (s.reciterPriority ?? []).compactMap { $0.order }.max() ?? -1
        let entry = ReciterPriorityEntry(order: maxOrder + 1, reciterId: reciterId)
        context.insert(entry)
        s.reciterPriority = (s.reciterPriority ?? []) + [entry]
        try? context.save()
        loadOrder()
    }

    private func removeEntry(_ entry: ReciterPriorityEntry) {
        guard let s = settings else { return }
        orderedEntries.removeAll { $0.id == entry.id }
        s.reciterPriority = (s.reciterPriority ?? []).filter { $0.id != entry.id }
        context.delete(entry)
        try? context.save()
    }

    private func enabledBinding(_ entry: ReciterPriorityEntry) -> Binding<Bool> {
        Binding(
            get: { entry.isEnabled ?? true },
            set: { entry.isEnabled = $0; try? context.save() }
        )
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
