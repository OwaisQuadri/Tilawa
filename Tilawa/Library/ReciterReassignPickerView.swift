import SwiftUI
import SwiftData

/// Lets the user pick an existing reciter to move a CDN source onto.
struct ReciterReassignPickerView: View {

    var source: ReciterCDNSource?
    let excludedReciter: Reciter
    let onAssigned: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Reciter.name) private var allReciters: [Reciter]

    var body: some View {
        NavigationStack {
            List {
                ForEach(allReciters.filter { $0.id != excludedReciter.id }) { reciter in
                    Button(reciter.safeName) {
                        assign(to: reciter)
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Assign to Reciter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func assign(to newReciter: Reciter) {
        guard let source else { dismiss(); return }
        source.reciter = newReciter
        newReciter.cdnSources = (newReciter.cdnSources ?? []) + [source]
        excludedReciter.cdnSources = (excludedReciter.cdnSources ?? []).filter { $0.id != source.id }
        if (excludedReciter.cdnSources ?? []).isEmpty && (excludedReciter.segments ?? []).isEmpty {
            if let id = excludedReciter.id {
                PlaybackSettings.cleanupPriorityEntries(for: id, in: context)
            }
            context.delete(excludedReciter)
        }
        try? context.save()
        dismiss()
        onAssigned()
    }
}
