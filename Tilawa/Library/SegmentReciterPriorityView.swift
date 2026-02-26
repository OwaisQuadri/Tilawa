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

    private let metadata = QuranMetadataService.shared

    private var navigationTitle: String {
        let startName = metadata.surahName(startSurah)
        let endName   = metadata.surahName(endSurah)
        if startSurah == endSurah {
            return "\(startName) \(startSurah):\(startAyah)–\(endAyah)"
        }
        return "\(startName) \(startSurah):\(startAyah) – \(endName) \(endSurah):\(endAyah)"
    }

    // Reciters with audio that are not yet in this segment's priority list
    private var unlistedReciters: [Reciter] {
        let listedIds = Set(orderedEntries.compactMap { $0.reciterId })
        return allReciters.filter { r in
            guard let id = r.id else { return false }
            return !listedIds.contains(id) && (r.hasCDN || r.hasPersonalRecordings)
        }.sorted { $0.safeName < $1.safeName }
    }

    var body: some View {
        List {
            rangeSection
            prioritySection

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
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadState() }
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
            .onDelete { indexSet in
                for i in indexSet {
                    removeEntry(orderedEntries[i])
                }
            }
        } header: {
            Text("Hold and drag to reorder for this segment.")
                .textCase(nil)
                .font(.caption)
        } footer: {
            Text("Swipe left to remove a reciter. The global default order applies outside this range.")
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
                        .foregroundStyle(.secondary)
                    if let style = reciter?.style, !style.isEmpty {
                        Text("· \(style.capitalized)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if reciter?.hasPersonalRecordings == true {
                        Label("Personal", systemImage: "person.wave.2")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: enabledBinding(entry))
                .labelsHidden()
                .controlSize(.small)
        }
        .opacity(entry.isEnabled == false ? 0.4 : 1.0)
    }

    // MARK: - State management

    private func loadState() {
        startSurah = segmentOverride.startSurah ?? 1
        startAyah  = segmentOverride.startAyah  ?? 1
        endSurah   = segmentOverride.endSurah   ?? 1
        endAyah    = segmentOverride.endAyah    ?? 7
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

    private func addToPriority(_ reciter: Reciter) {
        guard let reciterId = reciter.id else { return }
        let maxOrder = (segmentOverride.reciterPriority ?? []).compactMap { $0.order }.max() ?? -1
        let entry = SegmentReciterEntry(order: maxOrder + 1, reciterId: reciterId)
        context.insert(entry)
        segmentOverride.reciterPriority = (segmentOverride.reciterPriority ?? []) + [entry]
        try? context.save()
        loadState()
    }

    private func removeEntry(_ entry: SegmentReciterEntry) {
        orderedEntries.removeAll { $0.id == entry.id }
        segmentOverride.reciterPriority = (segmentOverride.reciterPriority ?? []).filter { $0.id != entry.id }
        context.delete(entry)
        try? context.save()
    }

    private func enabledBinding(_ entry: SegmentReciterEntry) -> Binding<Bool> {
        Binding(
            get: { entry.isEnabled ?? true },
            set: { entry.isEnabled = $0; try? context.save() }
        )
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
