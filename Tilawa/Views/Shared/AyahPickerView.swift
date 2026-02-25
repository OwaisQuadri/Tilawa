import SwiftUI

/// A picker for selecting an ayah number within a given surah.
struct AyahPickerView: View {
    let surah: Int
    @Binding var selection: Int
    private let metadata = QuranMetadataService.shared

    private var ayahCount: Int {
        metadata.ayahCount(surah: surah)
    }

    var body: some View {
        Picker("Ayah", selection: $selection) {
            ForEach(1...max(1, ayahCount), id: \.self) { ayah in
                Text("\(ayah)")
                    .tag(ayah)
            }
        }
        .pickerStyle(.wheel)
        .onChange(of: surah) { _, _ in
            // Clamp selection when surah changes
            if selection > ayahCount {
                selection = 1
            }
        }
    }
}
