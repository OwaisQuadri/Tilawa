import SwiftUI
import SwiftData

/// Sheet for assigning a surah:ayah range to an AyahMarker.
/// Start and end ayah are both optional — navigate into each picker and use "Clear" to unset.
struct AyahAssignmentView: View {

    let marker: AyahMarker
    /// The start ayah of the previous confirmed marker, used to seed smart defaults.
    let suggestedRef: AyahRef?
    let onAssign: (AyahRef?, AyahRef?) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedSurah: Int?
    @State private var selectedAyah: Int?
    @State private var selectedEndSurah: Int?
    @State private var selectedEndAyah: Int?
    @State private var showDeleteConfirm = false

    init(marker: AyahMarker,
         suggestedRef: AyahRef? = nil,
         onAssign: @escaping (AyahRef?, AyahRef?) -> Void,
         onDelete: @escaping () -> Void) {
        self.marker = marker
        self.suggestedRef = suggestedRef
        self.onAssign = onAssign
        self.onDelete = onDelete
        _selectedSurah    = State(initialValue: marker.assignedSurah)
        _selectedAyah     = State(initialValue: marker.assignedAyah)
        _selectedEndSurah = State(initialValue: marker.assignedEndSurah)
        _selectedEndAyah  = State(initialValue: marker.assignedEndAyah)
    }

    // Default for "ending at marker" picker:
    //   • start is set → ayah before start
    //   • neither set  → suggestedRef (prev marker's start)
    private func endPickerDefault() -> (surah: Int, ayah: Int) {
        if let sS = selectedSurah, let sA = selectedAyah {
            let meta = QuranMetadataService.shared
            if sA > 1 { return (sS, sA - 1) }
            if sS > 1 { return (sS - 1, meta.ayahCount(surah: sS - 1)) }
            return (1, 1)
        }
        return (suggestedRef?.surah ?? 1, suggestedRef?.ayah ?? 1)
    }

    // Default for "starting at marker" picker:
    //   • end is set  → ayah after end
    //   • neither set → ayah after suggestedRef (prev marker's start + 1)
    private func startPickerDefault() -> (surah: Int, ayah: Int) {
        let meta = QuranMetadataService.shared
        if let eS = selectedEndSurah, let eA = selectedEndAyah {
            if let next = meta.ayah(after: AyahRef(surah: eS, ayah: eA)) {
                return (next.surah, next.ayah)
            }
            return (eS, eA)
        }
        if let ref = suggestedRef, let next = meta.ayah(after: ref) {
            return (next.surah, next.ayah)
        }
        return (suggestedRef?.surah ?? 1, suggestedRef?.ayah ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        let d = endPickerDefault()
                        AyahPickerDetailView(
                            title: "Ayah ending at marker",
                            surah: $selectedEndSurah,
                            ayah: $selectedEndAyah,
                            defaultSurah: d.surah,
                            defaultAyah: d.ayah
                        )
                    } label: {
                        LabeledContent("Ayah ending at marker") {
                            Text(ayahLabel(surah: selectedEndSurah, ayah: selectedEndAyah))
                                .foregroundStyle(selectedEndSurah == nil ? .tertiary : .secondary)
                        }
                    }

                    NavigationLink {
                        let d = startPickerDefault()
                        AyahPickerDetailView(
                            title: "Ayah starting at marker",
                            surah: $selectedSurah,
                            ayah: $selectedAyah,
                            defaultSurah: d.surah,
                            defaultAyah: d.ayah
                        )
                    } label: {
                        LabeledContent("Ayah starting at marker") {
                            Text(ayahLabel(surah: selectedSurah, ayah: selectedAyah))
                                .foregroundStyle(selectedSurah == nil ? .tertiary : .secondary)
                        }
                    }
                } footer: {
                    Text("Set the ending ayah to close the previous segment here, and the starting ayah to open a new segment. Both are optional.")
                        .font(.caption)
                }

                Section {
                    Button("Delete Marker", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .confirmationDialog(
                        "Delete this marker?",
                        isPresented: $showDeleteConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .navigationTitle(timeLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        let startRef = selectedSurah.flatMap { s in
                            selectedAyah.map { a in AyahRef(surah: s, ayah: a) }
                        }
                        let endRef = selectedEndSurah.flatMap { s in
                            selectedEndAyah.map { a in AyahRef(surah: s, ayah: a) }
                        }
                        onAssign(startRef, endRef)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Helpers

    private func ayahLabel(surah: Int?, ayah: Int?) -> String {
        guard let s = surah, let a = ayah else { return "Optional" }
        return "\(QuranMetadataService.shared.surahName(s)) \(s):\(a)"
    }

    private var timeLabel: String {
        let secs = marker.positionSeconds ?? 0
        let m  = Int(secs) / 60
        let s  = Int(secs) % 60
        let ms = Int((secs - Double(Int(secs))) * 10)
        return String(format: "Marker at %d:%02d.%d", m, s, ms)
    }
}

// MARK: - AyahPickerDetailView

/// Picker pushed via NavigationLink inside AyahAssignmentView.
/// Writes back to parent bindings on disappear; "Clear" sets both to nil.
struct AyahPickerDetailView: View {

    let title: String
    @Binding var surah: Int?
    @Binding var ayah: Int?

    @Environment(\.dismiss) private var dismiss

    @State private var localSurah: Int
    @State private var localAyah: Int
    @State private var didClear = false

    init(title: String, surah: Binding<Int?>, ayah: Binding<Int?>, defaultSurah: Int = 1, defaultAyah: Int = 1) {
        self.title = title
        _surah = surah
        _ayah  = ayah
        _localSurah = State(initialValue: surah.wrappedValue ?? defaultSurah)
        _localAyah  = State(initialValue: ayah.wrappedValue ?? defaultAyah)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 0) {
                    SurahPickerView(selection: $localSurah)
                        .frame(maxWidth: .infinity)
                    AyahPickerView(surah: localSurah, selection: $localAyah)
                        .frame(width: 80)
                }
                .frame(height: 160)
                .onChange(of: localSurah) { _, _ in clamp() }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear") {
                    surah = nil
                    ayah  = nil
                    didClear = true
                    dismiss()
                }
                .foregroundStyle(.red)
            }
        }
        .onDisappear {
            // Write through only if user didn't clear
            if !didClear {
                surah = localSurah
                ayah  = localAyah
            }
        }
    }

    private func clamp() {
        let maxAyah = QuranMetadataService.shared.ayahCount(surah: localSurah)
        if localAyah > maxAyah { localAyah = maxAyah }
    }
}
