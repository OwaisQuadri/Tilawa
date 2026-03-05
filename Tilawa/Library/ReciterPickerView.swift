import SwiftUI
import SwiftData

/// Searchable list of all reciters in the DB. Tapping one assigns it to the recording.
struct ReciterPickerView: View {

    let recording: Recording

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Reciter.name) private var allReciters: [Reciter]
    @State private var searchText = ""
    @State private var showCreateSheet = false

    private var filteredReciters: [Reciter] {
        guard !searchText.isEmpty else { return allReciters }
        let q = searchText.lowercased()
        return allReciters.filter {
            ($0.name?.lowercased().contains(q) == true) ||
            $0.riwayahSummary.contains { $0.riwayah.displayName.lowercased().contains(q) }
        }
    }

    var body: some View {
        List {
            // "New Reciter" option
            Button {
                showCreateSheet = true
            } label: {
                Label("New Reciter…", systemImage: "plus.circle")
                    .foregroundStyle(Color.accentColor)
            }

            // "None" option
            Button {
                assign(nil)
            } label: {
                HStack {
                    Text("None")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if recording.reciter == nil {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
            }
            .foregroundStyle(.primary)

            ForEach(filteredReciters, id: \.id) { reciter in
                Button {
                    assign(reciter)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reciter.safeName)
                                .foregroundStyle(.primary)
                            HStack(spacing: 4) {
                                Text(reciter.riwayahSummaryLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if reciter.hasCDN {
                                    Label("CDN", systemImage: "icloud")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        Spacer()
                        if recording.reciter?.id == reciter.id {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search reciters")
        .navigationTitle("Assign Reciter")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { deleteOrphanReciters() }
        .sheet(isPresented: $showCreateSheet) {
            CreateReciterSheet { newReciter in
                assign(newReciter)
            }
        }
    }

    private func assign(_ reciter: Reciter?) {
        let previous = recording.reciter
        recording.reciter = reciter
        // If the previous reciter is now an orphan, delete it immediately
        if let previous, previous.id != reciter?.id, !previous.hasCDN, !previous.hasPersonalRecordings {
            if let id = previous.id {
                PlaybackSettings.cleanupPriorityEntries(for: id, in: context)
            }
            context.delete(previous)
        }
        try? context.save()
        dismiss()
    }

    private func deleteOrphanReciters() {
        let orphans = allReciters.filter { !$0.hasCDN && !$0.hasPersonalRecordings }
        guard !orphans.isEmpty else { return }
        orphans.forEach { reciter in
            if let id = reciter.id {
                PlaybackSettings.cleanupPriorityEntries(for: id, in: context)
            }
            context.delete(reciter)
        }
        try? context.save()
    }
}

// MARK: - Create Reciter Sheet

struct CreateReciterSheet: View {
    let onCreate: (Reciter) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
            }
            .navigationTitle("New Reciter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let r = Reciter()
                        r.id = UUID()
                        r.name = name.trimmingCharacters(in: .whitespaces)
                        context.insert(r)
                        try? context.save()
                        onCreate(r)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
