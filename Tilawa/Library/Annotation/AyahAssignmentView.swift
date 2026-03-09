import SwiftUI
import SwiftData

/// Sheet for assigning a surah:ayah range to an AyahMarker.
/// Start and end ayah are both optional — navigate into each picker and use "Clear" to unset.
struct AyahAssignmentView: View {

    let marker: AyahMarker
    /// The start ayah of the previous confirmed marker, used to seed smart defaults.
    let suggestedRef: AyahRef?
    /// Ayah refs already assigned to other markers in this recording (for duplicate detection).
    let existingAyahRefs: Set<AyahRef>
    let onAssign: (AyahRef?, AyahRef?) -> Void
    var onMarkerTypeChanged: ((AyahMarker.MarkerType) -> Void)?
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Reciter.name) private var allReciters: [Reciter]

    @State private var selectedMarkerType: AyahMarker.MarkerType
    @State private var selectedSurah: Int?
    @State private var selectedAyah: Int?
    @State private var selectedEndSurah: Int?
    @State private var selectedEndAyah: Int?
    @State private var selectedReciterID: UUID?
    @State private var selectedRiwayah: Riwayah?
    @State private var showDeleteConfirm = false

    init(marker: AyahMarker,
         suggestedRef: AyahRef? = nil,
         existingAyahRefs: Set<AyahRef> = [],
         onAssign: @escaping (AyahRef?, AyahRef?) -> Void,
         onMarkerTypeChanged: ((AyahMarker.MarkerType) -> Void)? = nil,
         onDelete: @escaping () -> Void) {
        self.marker = marker
        self.suggestedRef = suggestedRef
        self.existingAyahRefs = existingAyahRefs
        self.onAssign = onAssign
        self.onMarkerTypeChanged = onMarkerTypeChanged
        self.onDelete = onDelete
        _selectedMarkerType = State(initialValue: marker.resolvedMarkerType)
        _selectedSurah      = State(initialValue: marker.assignedSurah)
        _selectedAyah       = State(initialValue: marker.assignedAyah)
        _selectedEndSurah   = State(initialValue: marker.assignedEndSurah)
        _selectedEndAyah    = State(initialValue: marker.assignedEndAyah)
        _selectedReciterID  = State(initialValue: marker.reciterID)
        _selectedRiwayah    = State(initialValue: Riwayah(rawValue: marker.riwayah ?? ""))
    }

    private var startAyahSelected: Bool { selectedSurah != nil && selectedAyah != nil }
    private var confirmDisabled: Bool {
        guard selectedMarkerType == .ayah else { return false }
        return startAyahSelected && (selectedReciterID == nil || selectedRiwayah == nil)
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
                Section("Marker Type") {
                    Picker("Type", selection: $selectedMarkerType) {
                        Text("Ayah").tag(AyahMarker.MarkerType.ayah)
                        Text("Crop After").tag(AyahMarker.MarkerType.cropAfter)
                        Text("Crop Before").tag(AyahMarker.MarkerType.cropBefore)
                    }
                    .pickerStyle(.segmented)
                }

                if selectedMarkerType == .ayah {
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
                            LabeledContent("Ayah Ending at Marker") {
                                Text(ayahLabel(surah: selectedEndSurah, ayah: selectedEndAyah))
                                    .foregroundStyle(selectedEndSurah == nil ? .tertiary : .secondary)
                            }
                        }
                    }

                    Section {
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
                            LabeledContent("Ayah Starting at Marker") {
                                Text(ayahLabel(surah: selectedSurah, ayah: selectedAyah))
                                    .foregroundStyle(selectedSurah == nil ? .tertiary : .secondary)
                            }
                        }

                        if let s = selectedSurah, let a = selectedAyah,
                           existingAyahRefs.contains(AyahRef(surah: s, ayah: a)) {
                            Label("This ayah has an earlier segment in this recording",
                                  systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if startAyahSelected {
                            let reciterName = allReciters.first(where: { $0.id == selectedReciterID })?.safeName
                            NavigationLink {
                                ReciterPickerView(selectedID: selectedReciterID) { id in
                                    selectedReciterID = id
                                }
                            } label: {
                                LabeledContent("Reciter") {
                                    Text(reciterName ?? "")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            NavigationLink {
                                RiwayahPickerView(selectedRiwayah: selectedRiwayah) { riwayah in
                                    selectedRiwayah = riwayah
                                }
                            } label: {
                                LabeledContent("Riwayah") {
                                    Text(selectedRiwayah?.displayName ?? "")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
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
                        onMarkerTypeChanged?(selectedMarkerType)
                        if selectedMarkerType == .ayah {
                            let startRef = selectedSurah.flatMap { s in
                                selectedAyah.map { a in AyahRef(surah: s, ayah: a) }
                            }
                            let endRef = selectedEndSurah.flatMap { s in
                                selectedEndAyah.map { a in AyahRef(surah: s, ayah: a) }
                            }
                            marker.reciterID = selectedReciterID
                            marker.riwayah   = selectedRiwayah?.rawValue
                            onAssign(startRef, endRef)
                        } else {
                            // Crop markers: clear ayah assignments, mark confirmed
                            marker.assignedSurah = nil
                            marker.assignedAyah = nil
                            marker.assignedEndSurah = nil
                            marker.assignedEndAyah = nil
                            marker.isConfirmed = true
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(confirmDisabled)
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

// MARK: - ReciterPickerView

/// Navigation-pushed reciter selection list with inline "New Reciter" creation.
struct ReciterPickerView: View {

    let selectedID: UUID?
    let onSelect: (UUID?) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Reciter.name) private var reciters: [Reciter]

    @State private var showNewReciterAlert = false
    @State private var newReciterName = ""

    var body: some View {
        List {
            Button("None") {
                onSelect(nil)
                dismiss()
            }
            .foregroundStyle(.red)

            ForEach(reciters) { reciter in
                Button {
                    onSelect(reciter.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(reciter.safeName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if reciter.id == selectedID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Reciter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Reciter", systemImage: "plus") {
                    newReciterName = ""
                    showNewReciterAlert = true
                }
            }
        }
        .alert("New Reciter", isPresented: $showNewReciterAlert) {
            TextField("Name", text: $newReciterName)
            Button("Add") {
                let trimmed = newReciterName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let reciter = Reciter()
                reciter.id = UUID()
                reciter.name = trimmed
                reciter.localCacheDirectory = reciter.id!.uuidString
                context.insert(reciter)
                try? context.save()
                onSelect(reciter.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new reciter.")
        }
    }
}

// MARK: - RiwayahPickerView

/// Navigation-pushed riwayah selection list.
struct RiwayahPickerView: View {

    let selectedRiwayah: Riwayah?
    let onSelect: (Riwayah?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(Riwayah.allCases, id: \.self) { riwayah in
                Button {
                    onSelect(riwayah)
                    dismiss()
                } label: {
                    HStack {
                        Text(riwayah.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if riwayah == selectedRiwayah {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Riwayah")
        .navigationBarTitleDisplayMode(.inline)
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
