import Foundation

/// Loads and caches QUL page layout data from bundled JSON files.
actor PageLayoutProvider {
    static let shared = PageLayoutProvider()

    private var cache: [Int: QULPageLayout] = [:]

    /// Load layout for a specific page (1-604). Returns from cache if available.
    func layout(for page: Int) throws -> QULPageLayout {
        if let cached = cache[page] { return cached }

        let fileName = String(format: "page%03d", page)
        guard let url = Bundle.main.url(forResource: fileName,
                                         withExtension: "json") else {
            throw QuranDataError.pageNotFound(page)
        }
        let data = try Data(contentsOf: url)
        var layout = try JSONDecoder().decode(QULPageLayout.self, from: data)
        layout = Self.correctPageLayout(layout)
        cache[page] = layout
        return layout
    }

    // MARK: - QUL Data Corrections

    /// Fix known QUL data issues in page layouts.
    private static func correctPageLayout(_ layout: QULPageLayout) -> QULPageLayout {
        var lines = layout.lines

        // Fix 1: Surah headers with wrong surah number.
        // QUL bug: some headers show the current surah instead of the next surah.
        // Detect: if the header's surah matches a preceding text line's surah, increment.
        for i in lines.indices where lines[i].type == .surahHeader {
            guard let headerSurah = lines[i].surah,
                  let headerSurahNum = Int(headerSurah),
                  headerSurahNum < 114 else { continue }

            let precedingTextSurahs = Set(
                lines[0..<i]
                    .filter { $0.type == .text }
                    .compactMap { $0.words?.first?.ayahRef.surah }
            )

            if precedingTextSurahs.contains(headerSurahNum) {
                lines[i] = QULLine(
                    line: lines[i].line, type: .surahHeader,
                    text: lines[i].text,
                    surah: String(format: "%03d", headerSurahNum + 1),
                    verseRange: lines[i].verseRange,
                    words: lines[i].words,
                    qpcV2: lines[i].qpcV2, qpcV1: lines[i].qpcV1
                )
            }
        }

        // Fix 2: Pages with text starting from verse 1 but missing surah header + basmala.
        // Some QUL pages only contain text lines without the header/basmala that should precede them.
        if let firstTextIdx = lines.firstIndex(where: { $0.type == .text }),
           let firstWord = lines[firstTextIdx].words?.first,
           firstWord.ayahRef.ayah == 1 {

            let surahNum = firstWord.ayahRef.surah
            let hasHeader = lines[0..<firstTextIdx].contains { $0.type == .surahHeader }
            let hasBasmala = lines[0..<firstTextIdx].contains { $0.type == .basmala }

            if !hasHeader && !hasBasmala {
                let needsBasmala = surahNum != 1 && surahNum != 9
                var newLines: [QULLine] = []

                newLines.append(QULLine(
                    line: 1, type: .surahHeader, text: nil,
                    surah: String(format: "%03d", surahNum),
                    verseRange: nil, words: nil, qpcV2: nil, qpcV1: nil
                ))

                if needsBasmala {
                    newLines.append(QULLine(
                        line: 2, type: .basmala,
                        text: "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ",
                        surah: nil, verseRange: nil, words: nil,
                        qpcV2: nil, qpcV1: nil
                    ))
                }

                let offset = newLines.count
                for line in lines {
                    newLines.append(QULLine(
                        line: line.line + offset, type: line.type,
                        text: line.text, surah: line.surah,
                        verseRange: line.verseRange, words: line.words,
                        qpcV2: line.qpcV2, qpcV1: line.qpcV1
                    ))
                }

                lines = newLines
            }
        }

        // Fix 3: Add trailing surah header when a surah ends with room on the page.
        // If the last text line is the final verse of a surah and there's space, add the next surah's header.
        if let lastTextLine = lines.last(where: { $0.type == .text }),
           let lastWord = lastTextLine.words?.last {
            let surahNum = lastWord.ayahRef.surah
            let ayah = lastWord.ayahRef.ayah
            let ayahCount = QuranMetadataService.shared.ayahCount(surah: surahNum)
            let maxLine = lines.map(\.line).max() ?? 0

            if ayah == ayahCount, surahNum > 1, surahNum < 114, maxLine < 15 {
                let hasTrailingHeader = lines.contains {
                    $0.type == .surahHeader && $0.line > lastTextLine.line
                }
                if !hasTrailingHeader {
                    lines.append(QULLine(
                        line: maxLine + 1, type: .surahHeader, text: nil,
                        surah: String(format: "%03d", surahNum + 1),
                        verseRange: nil, words: nil, qpcV2: nil, qpcV1: nil
                    ))
                }
            }
        }

        return QULPageLayout(page: layout.page, lines: lines)
    }

    /// Evict pages outside a window to control memory.
    func evict(outside range: ClosedRange<Int>) {
        cache = cache.filter { range.contains($0.key) }
    }

    /// Clear entire cache.
    func clearCache() {
        cache.removeAll()
    }

    /// Number of cached pages (for testing).
    var cacheCount: Int { cache.count }
}
