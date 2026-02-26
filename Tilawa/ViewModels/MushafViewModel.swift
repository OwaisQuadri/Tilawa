import SwiftUI
import CoreText
import Observation

@Observable
final class MushafViewModel {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let currentPage = "mushaf.currentPage"
        static let fontSize    = "mushaf.fontSize"
        static let theme       = "mushaf.theme"
    }

    // MARK: - Page State

    var currentPage: Int = 1 {
        didSet { UserDefaults.standard.set(currentPage, forKey: Keys.currentPage) }
    }
    var showJumpSheet: Bool = false
    var currentPageAyahRange: (first: AyahRef, last: AyahRef)? = nil

    // MARK: - Highlighting

    var highlightedAyah: AyahRef?
    /// The exact page where highlightedAyah lives — set by scrollToAyah (playback)
    /// or handleWordTap (user tap). Nil means "use estimate / currentPageAyahRange".
    var highlightedAyahPage: Int?
    var highlightedWord: MushafPageUIView.WordLocation?

    // MARK: - Theme

    var theme: MushafTheme = .standard {
        didSet { UserDefaults.standard.set(theme.name, forKey: Keys.theme) }
    }

    // MARK: - Font

    private let fontProvider: QuranFontProvider
    var fontSize: CGFloat = 22.0 {
        didSet { UserDefaults.standard.set(Double(fontSize), forKey: Keys.fontSize) }
    }

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

        let savedPage = UserDefaults.standard.integer(forKey: Keys.currentPage)
        if savedPage > 0 { currentPage = savedPage }

        let savedFontSize = UserDefaults.standard.double(forKey: Keys.fontSize)
        if savedFontSize > 0 { fontSize = CGFloat(savedFontSize) }

        if let savedThemeName = UserDefaults.standard.string(forKey: Keys.theme) {
            // "Light" and "Dark" are legacy saved values → map to .standard
            theme = [MushafTheme.standard, .sepia].first { $0.name == savedThemeName } ?? .standard
        }
    }

    // MARK: - Word Tap / Long-Press Handling

    func handleWordTap(_ wordLocation: MushafPageUIView.WordLocation) {
        // Intentionally no-op: tapping words should not highlight anything
    }

    /// Set when the user long-presses an ayah — used to pre-seed PlaybackSetupSheet.
    var longPressedAyahRef: AyahRef? = nil
    var showAyahContextMenu: Bool = false

    var longPressedAyahTitle: String {
        guard let ref = longPressedAyahRef else { return "" }
        return "\(metadata.surahName(ref.surah)) \(ref.surah):\(ref.ayah)"
    }

    func handleWordLongPress(_ wordLocation: MushafPageUIView.WordLocation) {
        longPressedAyahRef = wordLocation.ayahRef
        showAyahContextMenu = true
    }

    // MARK: - Page-Scoped Highlight Queries

    func highlightedWordOnPage(_ page: Int) -> MushafPageUIView.WordLocation? {
        guard highlightedWord?.pageNumber == page else { return nil }
        return highlightedWord
    }

    func highlightedAyahOnPage(_ page: Int) -> AyahRef? {
        guard let ayah = highlightedAyah else { return nil }
        // Use the confirmed exact page if available (set by scrollToAyah or handleWordTap).
        if let exactPage = highlightedAyahPage {
            return page == exactPage ? ayah : nil
        }
        // For the current page, use the actual rendered ayah range.
        if page == currentPage, let range = currentPageAyahRange {
            return RubService.ayah(ayah, isBetween: range.first, and: range.last) ? ayah : nil
        }
        // Fallback: rub-level page estimate.
        return metadata.page(for: ayah) == page ? ayah : nil
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

    // MARK: - Playback-driven scroll

    private var scrollTask: Task<Void, Never>?

    /// Navigates to the exact page containing `ayah`, using the PageLayoutProvider cache
    /// (which already holds recently-visited pages) to verify rather than estimating.
    func scrollToAyah(_ ayah: AyahRef) {
        scrollTask?.cancel()
        scrollTask = Task { [weak self] in
            guard let self else { return }
            let estimated = self.metadata.page(for: ayah)
            let ayahKey   = RubService.ayahKey(ayah)

            for delta in [0, 1, -1, 2, -2] {
                guard !Task.isCancelled else { return }
                let candidate = estimated + delta
                guard (1...604).contains(candidate) else { continue }
                guard let layout = try? await PageLayoutProvider.shared.layout(for: candidate)
                else { continue }
                let words = layout.lines.compactMap(\.words).flatMap { $0 }
                if let first = words.first?.ayahRef, let last = words.last?.ayahRef {
                    let firstKey = RubService.ayahKey(first)
                    let lastKey  = RubService.ayahKey(last)
                    if ayahKey >= firstKey && ayahKey <= lastKey {
                        await MainActor.run {
                            if candidate != self.currentPage { self.currentPage = candidate }
                        }
                        return
                    }
                }
            }
            // Fallback: use the estimate
            await MainActor.run {
                if estimated != self.currentPage { self.currentPage = estimated }
            }
        }
    }

    // MARK: - Page Changed

    private var pageChangeTask: Task<Void, Never>?

    func onPageChanged(to page: Int) {
        currentPage = page
        pageChangeTask?.cancel()
        pageChangeTask = Task {
            let layoutRange = max(1, page - 5)...min(604, page + 5)
            let fontRange   = max(1, page - 15)...min(604, page + 15)

            await PageLayoutProvider.shared.evict(outside: layoutRange)
            fontProvider.unregisterQCFFonts(outside: fontRange)

            guard !Task.isCancelled else { return }
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
