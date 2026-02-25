import SwiftUI

/// A picker for selecting a surah from the list of 114 surahs.
struct SurahPickerView: View {
    @Binding var selection: Int
    private let metadata = QuranMetadataService.shared

    var body: some View {
        Picker("Surah", selection: $selection) {
            ForEach(metadata.surahs, id: \.number) { surah in
                HStack {
                    Text("\(surah.number).")
                        .foregroundStyle(.secondary)
                    Text(surah.name)
                    Text(surah.englishName)
                        .foregroundStyle(.secondary)
                }
                .tag(surah.number)
            }
        }
        .pickerStyle(.wheel)
    }
}
