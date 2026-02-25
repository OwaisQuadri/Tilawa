import SwiftUI

/// Sheet for jumping to a specific surah/ayah or page.
/// Three side-by-side wheel pickers: Surah | Ayah | Page.
/// Surah change resets ayah to 1 and syncs page.
/// Page change syncs surah/ayah to the first ayah of the surah on that page.
struct JumpToAyahSheet: View {
    @Environment(MushafViewModel.self) private var mushafVM
    @State private var selectedSurah: Int = 1
    @State private var selectedAyah: Int = 1
    @State private var selectedPage: Int = 1

    private let metadata = QuranMetadataService.shared

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Surah picker: number + Arabic name + English name
                Picker("Surah", selection: $selectedSurah) {
                    ForEach(metadata.surahs, id: \.number) { surah in
                        VStack(alignment: .center, spacing: 1) {
                            HStack(spacing: 5) {
                                Text("\(surah.number).")
                                    .foregroundStyle(.secondary)
                                Text(surah.name)
                                    .environment(\.layoutDirection, .rightToLeft)
                            }
                            Text(surah.englishName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(surah.number)
                    }
                }
                .pickerStyle(.wheel)
                .onChange(of: selectedSurah) { _, newSurah in
                    selectedAyah = 1
                    selectedPage = metadata.page(for: AyahRef(surah: newSurah, ayah: 1))
                }

                Divider()

                // Ayah picker: plain numbers, resets on surah change
                Picker("Ayah", selection: $selectedAyah) {
                    let count = max(1, metadata.ayahCount(surah: selectedSurah))
                    ForEach(1...count, id: \.self) { ayah in
                        Text("\(ayah)").tag(ayah)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: 70)
                .onChange(of: selectedAyah) { _, newAyah in
                    selectedPage = metadata.page(for: AyahRef(surah: selectedSurah, ayah: newAyah))
                }
                .onChange(of: selectedSurah) { _, newSurah in
                    let count = metadata.ayahCount(surah: newSurah)
                    if selectedAyah > count { selectedAyah = 1 }
                }

                Divider()

                // Page picker: plain numbers, syncs surah on cross-surah jump
                Picker("Page", selection: $selectedPage) {
                    ForEach(1...604, id: \.self) { page in
                        Text("\(page)").tag(page)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: 70)
                .onChange(of: selectedPage) { _, newPage in
                    if let surah = metadata.surahOnPage(newPage), surah.number != selectedSurah {
                        selectedSurah = surah.number
                        selectedAyah = 1
                    }
                }
            }
            .font(.subheadline)
            .navigationTitle("Jump to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        mushafVM.jumpTo(surah: selectedSurah, ayah: selectedAyah)
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { mushafVM.showJumpSheet = false }
                }
            }
            .onAppear {
                selectedPage = mushafVM.currentPage
                if let surah = metadata.surahOnPage(mushafVM.currentPage) {
                    selectedSurah = surah.number
                }
            }
        }
        .presentationDetents([.medium])
    }
}
