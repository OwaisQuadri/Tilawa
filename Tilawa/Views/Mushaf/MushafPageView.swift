import SwiftUI

/// Wraps the CoreText rendering for a single page with SwiftUI chrome:
/// background and padding.
struct MushafPageView: View {
    let pageNumber: Int
    @Environment(MushafViewModel.self)  private var mushafVM
    @Environment(PlaybackViewModel.self) private var playbackVM
    @State private var pageLayout: QULPageLayout?
    @State private var riwayahContent: RiwayahPageContent?

    /// Mushaf page content aspect ratio (width / height).
    /// Standard Madani mushaf text area is roughly 10.5cm × 14.5cm.
    private static let pageAspectRatio: CGFloat = 0.72

    /// Pages where text uses natural spacing (centered) instead of full-width justification.
    /// First 2 pages (Al-Fatiha) and last 10 pages (short surahs in Juz 30).
    private static let centeredPages: Set<Int> = Set(1...2).union(Set(600...604))

    /// The ayah to highlight on this specific page.
    /// During playback, checks directly against the page's own loaded layout — no estimation,
    /// no async relay. Falls back to the user-tap highlight when nothing is playing.
    private var activeHighlightedAyah: AyahRef? {
        if let hafsAyah = playbackVM.currentAyah, let layout = pageLayout {
            if let content = riwayahContent {
                // Non-Hafs: translate playback ayah to native ref, check against content
                guard let nativeRef = AyahOffsetService.shared.nativeRef(
                    for: hafsAyah, riwayah: mushafVM.activeRiwayah
                ) else { return nil }
                if content.ayahRefs.contains(nativeRef) { return nativeRef }
                return nil
            } else {
                // Hafs: check against QUL word positions
                let words = layout.lines.compactMap(\.words).flatMap { $0 }
                guard let first = words.first?.ayahRef, let last = words.last?.ayahRef else { return nil }
                let end = playbackVM.currentAyahEnd ?? hafsAyah
                if hafsAyah <= last && end >= first { return hafsAyah }
                return nil
            }
        }
        return mushafVM.highlightedAyahOnPage(pageNumber)
    }

    private var activeHighlightedAyahEnd: AyahRef? {
        guard let hafsEnd = playbackVM.currentAyahEnd else { return nil }
        guard playbackVM.currentAyah != nil else { return nil }
        if mushafVM.isHafs { return hafsEnd }
        return AyahOffsetService.shared.nativeRef(for: hafsEnd, riwayah: mushafVM.activeRiwayah)
    }

    /// Whether this page appears on the right side of an open mushaf (even pages are right).
    private var isRightSidePage: Bool { pageNumber % 2 == 0 }

    /// Font to use for rendering: QPC page font for Hafs, riwayah font for unicode text.
    private var pageFont: CTFont {
        mushafVM.isHafs ? mushafVM.font(forPage: pageNumber) : mushafVM.currentFont
    }

    @ViewBuilder
    private func pageRepresentable(layout: QULPageLayout) -> some View {
        MushafPageRepresentable(
            pageLayout: layout,
            font: pageFont,
            highlightedWord: mushafVM.highlightedWordOnPage(pageNumber),
            highlightedAyah: activeHighlightedAyah,
            highlightedAyahEnd: activeHighlightedAyahEnd,
            theme: mushafVM.theme,
            centeredPage: Self.centeredPages.contains(pageNumber),
            riwayahContent: riwayahContent,
            onWordTapped: { mushafVM.handleWordTap($0) },
            onWordLongPressed: { mushafVM.handleWordLongPress($0) }
        )
    }

    @ViewBuilder
    private var sideIndicatorOverlay: some View {
        if mushafVM.showSideIndicators {
            PageSideIndicator(
                isTrailing: isRightSidePage,
                color: mushafVM.theme.pageBorderColor
            )
        }
    }

    private var isUnicodeText: Bool { riwayahContent != nil }

    var body: some View {
        Group {
            if let layout = pageLayout {
                if isUnicodeText {
                    // Unicode text: let the view expand vertically to fit content
                    ScrollView(.vertical, showsIndicators: false) {
                        pageRepresentable(layout: layout)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                    }
                    .background(mushafVM.theme.backgroundColor)
                } else {
                    // Hafs glyph: fixed aspect ratio
                    pageRepresentable(layout: layout)
                        .aspectRatio(Self.pageAspectRatio, contentMode: .fit)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(mushafVM.theme.backgroundColor)
                        .overlay(alignment: isRightSidePage ? .trailing : .leading) {
                            sideIndicatorOverlay
                        }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            pageLayout = try? await PageLayoutProvider.shared.layout(for: pageNumber)
            if !mushafVM.isHafs && mushafVM.effectiveRenderingMode == .unicodeText {
                riwayahContent = try? await RiwayahPageLayoutBuilder.shared.build(
                    page: pageNumber, riwayah: mushafVM.activeRiwayah
                )
            }
        }
        .task(id: mushafVM.activeRiwayah) {
            if mushafVM.isHafs || mushafVM.effectiveRenderingMode != .unicodeText {
                riwayahContent = nil
            } else {
                riwayahContent = try? await RiwayahPageLayoutBuilder.shared.build(
                    page: pageNumber, riwayah: mushafVM.activeRiwayah
                )
            }
        }
    }
}

// MARK: - Page Side Indicator

/// Thin decorative border on the outer (binding) edge of the page.
private struct PageSideIndicator: View {
    let isTrailing: Bool
    let color: Color
    private let lineWidth: CGFloat = 2.0
    private let gradientWidth: CGFloat = 2.0

    var body: some View {
        HStack(spacing: 0) {
            if isTrailing {
                LinearGradient(
                    colors: [.clear, color.opacity(0.5)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: gradientWidth)
            }

            color
                .frame(width: lineWidth)

            if !isTrailing {
                LinearGradient(
                    colors: [color.opacity(0.5), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: gradientWidth)
            }
        }
    }
}
