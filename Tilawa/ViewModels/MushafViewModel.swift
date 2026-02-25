import SwiftUI
import CoreText
import Observation

@Observable
final class MushafViewModel {

    // MARK: - Page State

    var currentPage: Int = 1
    var showJumpSheet: Bool = false
    var currentPageAyahRange: (first: AyahRef, last: AyahRef)? = nil

    // MARK: - Highlighting

    var highlightedAyah: AyahRef?
    var highlightedWord: MushafPageUIView.WordLocation?

    // MARK: - Theme

    var theme: MushafTheme = .light

    // MARK: - Font

    private let fontProvider: QuranFontProvider
    var fontSize: CGFloat = 22.0

    var currentFont: CTFont {
        fontProvider.hafsFont(size: fontSize)
    }

    /// Returns the QCF V2 page-specific font for a given page number.
    func font(forPage page: Int) -> CTFont {
        fontProvider.qcfFont(page: page, size: fontSize)
    }

    // MARK: - Services

    let metadata: QuranMetadataService

    // MARK: - Init

    init(fontProvider: QuranFontProvider = .shared,
         metadata: QuranMetadataService = .shared) {
        self.fontProvider = fontProvider
        self.metadata = metadata
    }

    // MARK: - Word Tap Handling

    func handleWordTap(_ wordLocation: MushafPageUIView.WordLocation) {
        if highlightedWord == wordLocation {
            // Deselect on second tap
            highlightedWord = nil
            highlightedAyah = nil
        } else {
            highlightedWord = wordLocation
            highlightedAyah = wordLocation.ayahRef
        }
    }

    // MARK: - Page-Scoped Highlight Queries

    func highlightedWordOnPage(_ page: Int) -> MushafPageUIView.WordLocation? {
        guard highlightedWord?.pageNumber == page else { return nil }
        return highlightedWord
    }

    func highlightedAyahOnPage(_ page: Int) -> AyahRef? {
        guard let ayah = highlightedAyah,
              metadata.page(for: ayah) == page else { return nil }
        return highlightedAyah
    }

    // MARK: - Navigation

    func jumpTo(surah: Int, ayah: Int) {
        let ref = AyahRef(surah: surah, ayah: ayah)
        let page = metadata.page(for: ref)
        currentPage = page
        highlightedAyah = ref
        highlightedWord = nil
        showJumpSheet = false
    }

    func jumpToPage(_ page: Int) {
        currentPage = max(1, min(604, page))
        highlightedAyah = nil
        highlightedWord = nil
        showJumpSheet = false
    }

    // MARK: - Page Changed

    func onPageChanged(to page: Int) {
        currentPage = page
        Task {
            await PageLayoutProvider.shared.evict(
                outside: max(1, page - 5)...min(604, page + 5)
            )
            if let layout = try? await PageLayoutProvider.shared.layout(for: page) {
                let words = layout.lines.compactMap(\.words).flatMap { $0 }
                if let first = words.first?.ayahRef, let last = words.last?.ayahRef {
                    await MainActor.run { currentPageAyahRange = (first, last) }
                }
            }
        }
    }

    // MARK: - Font Size

    func increaseFontSize() { fontSize = min(QuranFontProvider.maxFontSize, fontSize + 1) }
    func decreaseFontSize() { fontSize = max(QuranFontProvider.minFontSize, fontSize - 1) }

    // MARK: - Current Surah Info

    var currentSurahName: String {
        metadata.surahOnPage(currentPage)?.name ?? ""
    }

    var currentSurahEnglishName: String {
        metadata.surahOnPage(currentPage)?.englishName ?? ""
    }
}
