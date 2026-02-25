import SwiftUI

/// Wraps the CoreText rendering for a single page with SwiftUI chrome:
/// background, padding, and page side indicator.
struct MushafPageView: View {
    let pageNumber: Int
    @Environment(MushafViewModel.self) private var mushafVM
    @State private var pageLayout: QULPageLayout?

    private var isRightSidePage: Bool { pageNumber % 2 == 0 }

    /// Mushaf page content aspect ratio (width / height).
    /// Standard Madani mushaf text area is roughly 10.5cm × 14.5cm.
    private static let pageAspectRatio: CGFloat = 0.72

    /// Pages where text uses natural spacing (centered) instead of full-width justification.
    /// First 2 pages (Al-Fatiha) and last 10 pages (short surahs in Juz 30).
    private static let centeredPages: Set<Int> = Set(1...2).union(Set(600...604))

    var body: some View {
        Group {
            if let layout = pageLayout {
                MushafPageRepresentable(
                    pageLayout: layout,
                    font: mushafVM.font(forPage: pageNumber),
                    highlightedWord: mushafVM.highlightedWordOnPage(pageNumber),
                    highlightedAyah: mushafVM.highlightedAyahOnPage(pageNumber),
                    theme: mushafVM.theme,
                    centeredPage: Self.centeredPages.contains(pageNumber),
                    onWordTapped: { mushafVM.handleWordTap($0) }
                )
                .aspectRatio(Self.pageAspectRatio, contentMode: .fit)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(mushafVM.theme.backgroundColor)
                .overlay(alignment: isRightSidePage ? .trailing : .leading) {
                    PageSideIndicator(
                        isTrailing: isRightSidePage,
                        color: mushafVM.theme.pageBorderColor
                    )
                }
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

// MARK: - Page Side Indicator

/// Thin decorative border on the outer (binding) edge of the page.
private struct PageSideIndicator: View {
    let isTrailing: Bool
    let color: Color
    let lineWidth: CGFloat = 2.0
    let gradientWidth = 2.0

    var gradientColor: Color {
        color.opacity(0.5)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if isTrailing {
                LinearGradient(
                    colors: [.clear, gradientColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: gradientWidth)
            }

            color
                .frame(width: lineWidth)

            if !isTrailing {
                LinearGradient(
                    colors: [gradientColor, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: gradientWidth)
            }
        }
    }
}
