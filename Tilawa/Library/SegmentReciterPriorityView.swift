import SwiftUI
import SwiftData

/// Detail view for configuring reciter priority for a specific ayah range segment override.
struct SegmentReciterPriorityView: View {

    let segmentOverride: ReciterSegmentOverride

    @Environment(\.modelContext) private var context

    @Query private var allReciters: [Reciter]

    @State private var startSurah: Int = 1
    @State private var startAyah:  Int = 1
    @State private var endSurah:   Int = 1
    @State private var endAyah:    Int = 7

    @State private var orderedEntries: [SegmentReciterEntry] = []
    @State private var hasInitialized = false

    private let metadata = QuranMetadataService.shared

    private var navigationTitle: String {
        let startName = metadata.surahName(startSurah)
        let endName   = metadata.surahName(endSurah)
        if startSurah == endSurah {
            return "\(startName) \(startSurah):\(startAyah)–\(endAyah)"
        }
        return "\(startName) \(startSurah):\(startAyah) – \(endName) \(endSurah):\(endAyah)"
    }

    var body: some View {
        List {
            rangeSection
            prioritySection
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasInitialized else { return }
            loadState()
            hasInitialized = true
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var rangeSection: some View {
        Section("Range") {
            NavigationLink {
                RangePickerView(title: "From", surah: $startSurah, ayah: $startAyah)
                    .onDisappear {
                        clampEndIfNeeded()
                        saveRange()
                    }
            } label: {
                LabeledContent("From") {
                    Text("\(metadata.surahName(startSurah)) · \(startSurah):\(startAyah)")
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                RangePickerView(title: "To", surah: $endSurah, ayah: $endAyah)
                    .onDisappear { saveRange() }
            } label: {
                LabeledContent("To") {
                    Text("\(metadata.surahName(endSurah)) · \(endSurah):\(endAyah)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var prioritySection: some View {
        Section {
            ForEach(orderedEntries, id: \.id) { entry in
                priorityRow(entry)
            }
            .onMove { from, to in
                orderedEntries.move(fromOffsets: from, toOffset: to)
                saveOrder()
            }
        } header: {
            Text("Hold and drag to reorder for this segment.")
                .textCase(nil)
                .font(.caption)
        } footer: {
            Text("The global default order applies outside this range.")
                .font(.caption)
        }
        .environment(\.editMode, .constant(.active))
    }

    @ViewBuilder
    private func priorityRow(_ entry: SegmentReciterEntry) -> some View {
        let reciter = allReciters.first { $0.id == entry.reciterId }

        HStack(spacing: 12) {
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

    // MARK: - State management

    private func loadState() {
        startSurah = segmentOverride.startSurah ?? 1
        startAyah  = segmentOverride.startAyah  ?? 1
        endSurah   = segmentOverride.endSurah   ?? 1
        endAyah    = segmentOverride.endAyah    ?? 7
        orderedEntries = (segmentOverride.reciterPriority ?? [])
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }

        // Auto-add any reciter with audio that isn't in this segment's list yet (at the bottom)
        let listedIds = Set(orderedEntries.compactMap { $0.reciterId })
        let unlisted = allReciters.filter { r in
            guard let id = r.id else { return false }
            return !listedIds.contains(id) && (r.hasCDN || r.hasPersonalRecordings)
        }
        guard !unlisted.isEmpty else { return }
        let maxOrder = orderedEntries.compactMap { $0.order }.max() ?? -1
        for (i, reciter) in unlisted.enumerated() {
            let segEntry = SegmentReciterEntry(order: maxOrder + 1 + i, reciterId: reciter.id!)
            context.insert(segEntry)
            segmentOverride.reciterPriority = (segmentOverride.reciterPriority ?? []) + [segEntry]
        }
        try? context.save()
        orderedEntries = (segmentOverride.reciterPriority ?? [])
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    private func saveRange() {
        segmentOverride.startSurah = startSurah
        segmentOverride.startAyah  = startAyah
        segmentOverride.endSurah   = endSurah
        segmentOverride.endAyah    = endAyah
        try? context.save()
    }

    private func saveOrder() {
        for (index, entry) in orderedEntries.enumerated() {
            entry.order = index
        }
        try? context.save()
    }

    private func clampEndIfNeeded() {
        if endSurah < startSurah {
            endSurah = startSurah
            endAyah  = metadata.ayahCount(surah: endSurah)
        } else if endSurah == startSurah && endAyah < startAyah {
            endAyah = startAyah
        }
    }
}
