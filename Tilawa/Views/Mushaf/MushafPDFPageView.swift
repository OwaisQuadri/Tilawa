import SwiftUI

/// Renders a single mushaf page from a downloaded PDF for riwayahs without text data.
struct MushafPDFPageView: View {
    let pageNumber: Int
    @Environment(MushafViewModel.self) private var mushafVM
    @Environment(\.colorScheme) private var colorScheme
    @State private var pageImage: UIImage?

    /// Reading downloadStates establishes @Observable tracking so the body
    /// re-evaluates when any download state changes.
    private var currentDownloadState: MushafPDFManager.DownloadState {
        if mushafVM.activeRiwayah == .hafs && mushafVM.mushafStyle == .indopak {
            return MushafPDFManager.shared.indopakDownloadState
        }
        return MushafPDFManager.shared.downloadState(for: mushafVM.activeRiwayah)
    }

    var body: some View {
        let state = currentDownloadState

        Group {
            if let image = pageImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .colorInvert(colorScheme == .dark)
            } else if state == .downloaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { renderPage() }
            } else {
                // PDF not downloaded — MushafView's overlay handles the download prompt
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.black : Color.white)
        .onChange(of: state) { _, newState in
            if newState == .downloaded {
                renderPage()
            }
        }
        .task { renderPage() }
        .task(id: mushafVM.activeRiwayah) {
            pageImage = nil
            renderPage()
        }
    }

    private func renderPage() {
        let width = UIScreen.main.bounds.width * UIScreen.main.scale
        if mushafVM.activeRiwayah == .hafs && mushafVM.mushafStyle == .indopak {
            pageImage = MushafPDFManager.shared.renderIndopakPage(pageNumber, width: width)
        } else {
            pageImage = MushafPDFManager.shared.renderPage(
                pageNumber, riwayah: mushafVM.activeRiwayah, width: width
            )
        }
    }
}

// MARK: - Conditional Color Invert

private extension View {
    @ViewBuilder
    func colorInvert(_ active: Bool) -> some View {
        if active {
            self.colorInvert()
        } else {
            self
        }
    }
}
