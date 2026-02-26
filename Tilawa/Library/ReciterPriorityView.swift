import SwiftUI
import SwiftData

/// Drag-to-reorder list of all reciters in playback priority order.
/// "Auto" mode in PlaybackSetupSheet resolves reciters top-to-bottom through this list.
struct ReciterPriorityView: View {

    @Environment(\.modelContext) private var context

    @Query private var allSettings: [PlaybackSettings]
    @Query private var allReciters: [Reciter]

    @State private var orderedEntries: [ReciterPriorityEntry] = []
    @State private var savedOrderIds: [UUID] = []

    private var settings: PlaybackSettings? { allSettings.first }

    private var hasUnsavedChanges: Bool {
        orderedEntries.compactMap { $0.id } != savedOrderIds
    }

    // Reciters that have no priority entry yet (only show reciters with actual audio sources)
    private var unlistedReciters: [Reciter] {
        let listedIds = Set(orderedEntries.compactMap { $0.reciterId })
        return allReciters.filter { r in
            guard let id = r.id else { return false }
            return !listedIds.contains(id) && (r.hasCDN || r.hasPersonalRecordings)
        }.sorted { $0.safeName < $1.safeName }
    }

    var body: some View {
        List {
            Section {
                ForEach(orderedEntries, id: \.id) { entry in
                    priorityRow(entry)
                }
                .onMove { from, to in
                    orderedEntries.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { indexSet in
                    for i in indexSet {
                        removeEntry(orderedEntries[i])
                    }
                }
            } header: {
                Text("Drag to set priority. Top reciter plays first in Auto mode.")
                    .textCase(nil)
                    .font(.caption)
            } footer: {
                Text("Swipe left to remove a reciter from the Auto list. Removed reciters still exist in your library.")
                    .font(.caption)
            }

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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button("Save") { saveOrder() }
                        .fontWeight(.semibold)
                        .disabled(!hasUnsavedChanges)
                    EditButton()
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .onAppear { loadOrder() }
        .onChange(of: settings?.reciterPriority?.count) { _, _ in
            // Re-sync if entries are added/removed externally (e.g. manifest import)
            loadOrder()
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

            // Enable/disable toggle
            Toggle("", isOn: enabledBinding(entry))
                .labelsHidden()
                .controlSize(.small)
        }
        .opacity(entry.isEnabled == false ? 0.4 : 1.0)
    }

    // MARK: - Order management

    private func loadOrder() {
        guard let s = settings else { return }
        orderedEntries = s.sortedReciterPriority
        savedOrderIds = orderedEntries.compactMap { $0.id }
    }

    private func saveOrder() {
        for (index, entry) in orderedEntries.enumerated() {
            entry.order = index
        }
        try? context.save()
        savedOrderIds = orderedEntries.compactMap { $0.id }
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
}
