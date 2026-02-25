import SwiftUI

/// Wraps the CoreText rendering for a single page, handling async data loading.
struct MushafPageView: View {
    let pageNumber: Int
    @Environment(MushafViewModel.self) private var mushafVM
    @State private var pageLayout: QULPageLayout?

    var body: some View {
        Group {
            if let layout = pageLayout {
                MushafPageRepresentable(
                    pageLayout: layout,
                    font: mushafVM.font(forPage: pageNumber),
                    highlightedWord: mushafVM.highlightedWordOnPage(pageNumber),
                    highlightedAyah: mushafVM.highlightedAyahOnPage(pageNumber),
                    theme: mushafVM.theme,
                    onWordTapped: { wordLocation in
                        mushafVM.handleWordTap(wordLocation)
                    }
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            pageLayout = try? await PageLayoutProvider.shared.layout(for: pageNumber)
        }
    }
}
