import SwiftUI

/// Bridges MushafPageUIView into SwiftUI.
struct MushafPageRepresentable: UIViewRepresentable {
    let pageLayout: QULPageLayout
    let font: CTFont
    var highlightedWord: MushafPageUIView.WordLocation?
    var highlightedAyah: AyahRef?
    var theme: MushafTheme
    var onWordTapped: ((MushafPageUIView.WordLocation) -> Void)?

    func makeUIView(context: Context) -> MushafPageUIView {
        let view = MushafPageUIView()
        view.isOpaque = true
        view.contentMode = .redraw
        view.pageFont = font
        view.pageLayout = pageLayout
        view.theme = theme
        view.onWordTapped = onWordTapped
        return view
    }

    func updateUIView(_ uiView: MushafPageUIView, context: Context) {
        uiView.pageFont = font
        uiView.pageLayout = pageLayout
        uiView.highlightedWord = highlightedWord
        uiView.highlightedAyah = highlightedAyah
        uiView.theme = theme
        uiView.onWordTapped = onWordTapped
    }
}
