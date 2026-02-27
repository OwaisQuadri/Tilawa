import SwiftUI

/// Wheel-picker sub-view for selecting a single ayah position (surah + ayah).
/// Pushed via NavigationLink from PlaybackSetupSheet for both Start and End picks.
///
/// `allowedAyahs`: nil = show all ayahs; non-nil = only show ayahs in the set
/// (future use for personal recordings with limited coverage).
struct RangePickerView: View {
    let title: String
    @Binding var surah: Int
    @Binding var ayah: Int
    /// Nil means all ayahs are available. Non-nil restricts the ayah wheel to this set.
    let allowedAyahs: Set<AyahRef>?

    @State private var localSurah: Int
    @State private var localAyah: Int
    @Environment(\.dismiss) private var dismiss
    private let metadata = QuranMetadataService.shared

    init(title: String,
         surah: Binding<Int>,
         ayah: Binding<Int>,
         allowedAyahs: Set<AyahRef>? = nil) {
        self.title = title
        self._surah = surah
        self._ayah = ayah
        self.allowedAyahs = allowedAyahs
        self._localSurah = State(initialValue: surah.wrappedValue)
        self._localAyah  = State(initialValue: ayah.wrappedValue)
    }

    // MARK: - Derived

    /// Surahs that have at least one available ayah.
    private var availableSurahs: [QuranMetadataService.SurahInfo] {
        guard let allowed = allowedAyahs else { return metadata.surahs }
        return metadata.surahs.filter { s in
            allowed.contains { $0.surah == s.number }
        }
    }

    /// Ayahs to show in the wheel for the current localSurah.
    private var availableAyahs: [Int] {
        let count = max(1, metadata.ayahCount(surah: localSurah))
        guard let allowed = allowedAyahs else {
            return Array(1...count)
        }
        let filtered = (1...count).filter { allowed.contains(AyahRef(surah: localSurah, ayah: $0)) }
        return filtered.isEmpty ? Array(1...count) : filtered
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Surah picker — filtered to surahs with available ayahs
            VStack(spacing: 0) {
                Text("Surah").font(.caption).foregroundStyle(.secondary)
                Picker("Surah", selection: $localSurah) {
                    ForEach(availableSurahs, id: \.number) { s in
                        HStack {
                            Text("\(s.number). \(s.englishName)")
                                .font(.caption)
                            Spacer()
                            Text(s.name)
                                .font(.caption2)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                        .tag(s.number)
                    }
                }
                .pickerStyle(.wheel)
                .onAppear {
                    // Snap to first available surah if current selection isn't available
                    if !availableSurahs.contains(where: { $0.number == localSurah }),
                       let first = availableSurahs.first {
                        localSurah = first.number
                    }
                }
                .onChange(of: localSurah) { _, _ in
                    // Clamp ayah to what's available in the new surah
                    if !availableAyahs.contains(localAyah) {
                        localAyah = availableAyahs.first ?? 1
                    }
                }
            }

            Divider()

            // Ayah picker — filtered to availableAyahs
            VStack(spacing: 0) {
                Text("Ayah").font(.caption).foregroundStyle(.secondary)
                Picker("Ayah", selection: $localAyah) {
                    ForEach(availableAyahs, id: \.self) { n in
                        Text("\(n)").font(.caption).tag(n)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: 60)
                .id(localSurah) // Recreate wheel when surah changes so it scrolls to top
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    surah = localSurah
                    ayah  = localAyah
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
