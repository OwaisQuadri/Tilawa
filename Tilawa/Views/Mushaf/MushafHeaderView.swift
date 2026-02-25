import SwiftUI

/// Displays current surah name and page number in the toolbar.
struct MushafHeaderView: View {
    @Environment(MushafViewModel.self) private var mushafVM

    var body: some View {
        VStack(spacing: 2) {
            Text(mushafVM.currentSurahName)
                .font(.headline)
            Text("Page \(mushafVM.currentPage)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
