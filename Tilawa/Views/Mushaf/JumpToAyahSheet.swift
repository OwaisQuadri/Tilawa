import SwiftUI

/// Sheet for jumping to a specific surah/ayah, page, juz, or hizb position.
/// Five side-by-side wheel pickers: Surah | Ayah | Page | Juz | Hizb
///
/// Sync architecture:
///   - selectedSurah, selectedAyah, selectedPage are @State (direct picker bindings)
///   - Juz and Hizb pickers use custom Bindings derived from selectedPage to avoid cascades
///   - onChange(surah) guards against re-firing when surah was set programmatically from a page change
struct JumpToAyahSheet: View {
    @Environment(MushafViewModel.self) private var mushafVM
    @State private var selectedSurah: Int = 1
    @State private var selectedAyah: Int = 1
    @State private var selectedPage: Int = 1

    private let metadata = QuranMetadataService.shared
    private let juzService = JuzService.shared

    // MARK: - Derived Bindings (no @State → no onChange cascade)

    private var juzBinding: Binding<Int> {
        Binding(
            get: { juzService.juz(forPage: selectedPage) },
            set: { newJuz in
                selectedPage = juzService.juzStartPage(newJuz)
            }
        )
    }

    /// Binding over thumun index (1–240). Each thumun = ¼ hizb.
    private var thumunBinding: Binding<Int> {
        Binding(
            get: { juzService.juzInfo(forPage: selectedPage).thumun },
            set: { newThumun in
                selectedPage = JuzService.thumunStartPages[newThumun - 1]
            }
        )
    }

    // MARK: - Helpers

    private func thumunLabel(_ t: Int) -> String {
        let hizb = (t - 1) / 4 + 1
        let fracs = ["", "¼", "½", "¾"]
        return "\(hizb)\(fracs[(t - 1) % 4])"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Surah picker
                VStack(spacing: 0) {
                    Text("Surah").font(.caption).foregroundStyle(.secondary)
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
                        // Guard: if current page already belongs to this surah, this was a
                        // programmatic update from onChange(page) — don't overwrite the page.
                        guard metadata.surahOnPage(selectedPage)?.number != newSurah else { return }
                        selectedAyah = 1
                        selectedPage = metadata.page(for: AyahRef(surah: newSurah, ayah: 1))
                    }
                }

                Divider()

                // Ayah picker
                VStack(spacing: 0) {
                    Text("Ayah").font(.caption).foregroundStyle(.secondary)
                    Picker("Ayah", selection: $selectedAyah) {
                        let count = max(1, metadata.ayahCount(surah: selectedSurah))
                        ForEach(1...count, id: \.self) { ayah in
                            Text("\(ayah)").tag(ayah)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: 70)
                    .id(selectedSurah) // Recreate wheel when surah changes so it scrolls to top
                    .onChange(of: selectedAyah) { _, newAyah in
                        selectedPage = metadata.page(for: AyahRef(surah: selectedSurah, ayah: newAyah))
                    }
                }

                Divider()

                // Page picker
                VStack(spacing: 0) {
                    Text("Page").font(.caption).foregroundStyle(.secondary)
                    Picker("Page", selection: $selectedPage) {
                        ForEach(1...604, id: \.self) { page in
                            Text("\(page)").tag(page)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: 70)
                    .onChange(of: selectedPage) { _, newPage in
                        if let surah = metadata.surahOnPage(newPage) {
                            selectedSurah = surah.number
                            // Binary search for the first ayah of this surah on newPage
                            let count = metadata.ayahCount(surah: surah.number)
                            var lo = 1, hi = count
                            while lo < hi {
                                let mid = (lo + hi) / 2
                                if metadata.page(for: AyahRef(surah: surah.number, ayah: mid)) < newPage {
                                    lo = mid + 1
                                } else {
                                    hi = mid
                                }
                            }
                            selectedAyah = lo
                        } else {
                            selectedAyah = 1
                        }
                    }
                }

                Divider()

                // Juz picker (custom Binding derived from selectedPage — no cascade)
                VStack(spacing: 0) {
                    Text("Juz").font(.caption).foregroundStyle(.secondary)
                    Picker("Juz", selection: juzBinding) {
                        ForEach(1...30, id: \.self) { juz in
                            Text("\(juz)").tag(juz)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: 70)
                    .id(juzService.juz(forPage: selectedPage)) // Scroll when juz changes
                }

                Divider()

                // Hizb picker — each row = ¼ hizb (thumun), 240 total
                VStack(spacing: 0) {
                    Text("Hizb").font(.caption).foregroundStyle(.secondary)
                    Picker("Hizb", selection: thumunBinding) {
                        ForEach(1...240, id: \.self) { t in
                            Text(thumunLabel(t)).tag(t)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: 70)
                    .id(juzService.juzInfo(forPage: selectedPage).thumun) // Scroll when thumun changes
                }
            }
            .font(.subheadline)
            .navigationTitle("Jump to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        mushafVM.jumpToPage(selectedPage)
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { mushafVM.showJumpSheet = false }
                }
            }
            .onAppear {
                let page = mushafVM.currentPage
                selectedPage = page
                if let surah = metadata.surahOnPage(page) {
                    selectedSurah = surah.number
                }
                selectedAyah = 1
            }
        }
        .presentationDetents([.medium])
    }
}
