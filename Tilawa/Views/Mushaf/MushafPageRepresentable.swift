import SwiftUI

/// Bridges MushafPageUIView into SwiftUI. Renders only Quran text — no background or chrome.
struct MushafPageRepresentable: UIViewRepresentable {
    let pageLayout: QULPageLayout
    let font: CTFont
    var highlightedWord: MushafPageUIView.WordLocation?
    var highlightedAyah: AyahRef?
    var theme: MushafTheme
    var centeredPage: Bool = false
    var onWordTapped: ((MushafPageUIView.WordLocation) -> Void)?

    func makeUIView(context: Context) -> MushafPageUIView {
        let view = MushafPageUIView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.contentMode = .redraw
        view.centeredPage = centeredPage
        view.pageFont = font
        view.pageLayout = pageLayout
        view.theme = theme
        view.onWordTapped = onWordTapped
        return view
    }

    func updateUIView(_ uiView: MushafPageUIView, context: Context) {
        uiView.centeredPage = centeredPage
        uiView.pageFont = font
        uiView.pageLayout = pageLayout
        uiView.highlightedWord = highlightedWord
        uiView.highlightedAyah = highlightedAyah
        uiView.theme = theme
        uiView.onWordTapped = onWordTapped
    }
}
