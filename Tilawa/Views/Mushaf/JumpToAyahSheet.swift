import SwiftUI

/// Sheet for jumping to a specific surah/ayah or page.
struct JumpToAyahSheet: View {
    @Environment(MushafViewModel.self) private var mushafVM
    @State private var selectedSurah: Int = 1
    @State private var selectedAyah: Int = 1
    @State private var selectedPage: Int = 1
    @State private var jumpMode: JumpMode = .surahAyah

    enum JumpMode: String, CaseIterable {
        case surahAyah = "Surah & Ayah"
        case page = "Page"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Jump by", selection: $jumpMode) {
                    ForEach(JumpMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch jumpMode {
                case .surahAyah:
                    SurahPickerView(selection: $selectedSurah)
                        .frame(height: 150)
                    AyahPickerView(surah: selectedSurah, selection: $selectedAyah)
                        .frame(height: 150)
                case .page:
                    Picker("Page", selection: $selectedPage) {
                        ForEach(1...604, id: \.self) { page in
                            Text("Page \(page)").tag(page)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 200)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Jump to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        switch jumpMode {
                        case .surahAyah:
                            mushafVM.jumpTo(surah: selectedSurah, ayah: selectedAyah)
                        case .page:
                            mushafVM.jumpToPage(selectedPage)
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        mushafVM.showJumpSheet = false
                    }
                }
            }
            .onAppear {
                selectedPage = mushafVM.currentPage
                if let surah = mushafVM.metadata.surahOnPage(mushafVM.currentPage) {
                    selectedSurah = surah.number
                }
            }
        }
        .presentationDetents([.medium])
    }
}
