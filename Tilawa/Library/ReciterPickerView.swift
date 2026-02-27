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
            $0.safeRiwayah.displayName.lowercased().contains(q)
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
                                Text(reciter.safeRiwayah.displayName)
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
        recording.reciter = reciter
        try? context.save()
        dismiss()
    }

    private func deleteOrphanReciters() {
        let orphans = allReciters.filter { !$0.hasCDN && !$0.hasPersonalRecordings }
        guard !orphans.isEmpty else { return }
        orphans.forEach { context.delete($0) }
        try? context.save()
    }
}

// MARK: - Create Reciter Sheet

struct CreateReciterSheet: View {
    let onCreate: (Reciter) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var riwayah: Riwayah = .hafs

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Riwayah", selection: $riwayah) {
                    ForEach(Riwayah.allCases, id: \.self) { r in
                        Text(r.displayName).tag(r)
                    }
                }
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
                        r.riwayah = riwayah.rawValue
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
