import SwiftUI
import UIKit

/// Bridges MushafPageUIView into SwiftUI. Renders only Quran text — no background or chrome.
struct MushafPageRepresentable: UIViewRepresentable {
    let pageLayout: QULPageLayout
    let font: CTFont
    var highlightedWord: MushafPageUIView.WordLocation?
    var highlightedAyah: AyahRef?
    var highlightedAyahEnd: AyahRef?
    var theme: MushafTheme
    var centeredPage: Bool = false
    var onWordTapped: ((MushafPageUIView.WordLocation) -> Void)?
    var onWordLongPressed: ((MushafPageUIView.WordLocation) -> Void)?

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var parent: MushafPageRepresentable
        weak var managedView: MushafPageUIView?

        init(_ parent: MushafPageRepresentable) {
            self.parent = parent
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let view = managedView else { return }
            let location = gesture.location(in: view)
            guard let wordLocation = view.wordAt(point: location) else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onWordLongPressed?(wordLocation)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - UIViewRepresentable

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

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.4
        longPress.cancelsTouchesInView = false   // don't block tap delivery
        view.addGestureRecognizer(longPress)
        context.coordinator.managedView = view

        return view
    }

    func updateUIView(_ uiView: MushafPageUIView, context: Context) {
        context.coordinator.parent = self
        uiView.centeredPage = centeredPage
        uiView.pageFont = font
        uiView.pageLayout = pageLayout
        uiView.highlightedWord = highlightedWord
        uiView.highlightedAyah = highlightedAyah
        uiView.highlightedAyahEnd = highlightedAyahEnd
        uiView.theme = theme
        uiView.onWordTapped = onWordTapped
    }
}
