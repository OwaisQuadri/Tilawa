import Foundation

/// Provides static Quran reference data: surah names, ayah counts, page ranges.
/// Uses the Hafs an Asim standard (6,236 ayaat, 604 pages).
final class QuranMetadataService: Sendable {
    static let shared = QuranMetadataService()

    let surahs: [SurahInfo]
    private let pageToSurahStart: [Int: Int]  // startPage -> surah number

    struct SurahInfo: Codable, Sendable {
        let number: Int
        let name: String
        let englishName: String
        let ayahCount: Int
        let startPage: Int
    }

    private struct MetadataRoot: Codable {
        let surahs: [SurahInfo]
    }

    init() {
        guard let url = Bundle.main.url(forResource: "quran-metadata",
                                         withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(MetadataRoot.self, from: data) else {
            fatalError("Failed to load quran-metadata.json from bundle")
        }
        self.surahs = root.surahs

        var mapping: [Int: Int] = [:]
        for s in root.surahs {
            mapping[s.startPage] = s.number
        }
        self.pageToSurahStart = mapping
    }

    /// Testable initializer with explicit data.
    init(surahs: [SurahInfo]) {
        self.surahs = surahs
        var mapping: [Int: Int] = [:]
        for s in surahs {
            mapping[s.startPage] = s.number
        }
        self.pageToSurahStart = mapping
    }

    // MARK: - Queries

    func surah(_ number: Int) -> SurahInfo? {
        guard number >= 1, number <= surahs.count else { return nil }
        return surahs[number - 1]
    }

    func surahName(_ number: Int) -> String {
        surah(number)?.name ?? ""
    }

    func ayahCount(surah: Int) -> Int {
        self.surah(surah)?.ayahCount ?? 0
    }

    /// Returns the page number for a given ayah reference.
    /// Uses binary search on surah start pages + proportional estimation.
    func page(for ref: AyahRef) -> Int {
        guard let info = surah(ref.surah) else { return 1 }
        let nextSurahStart = ref.surah < 114
            ? (surah(ref.surah + 1)?.startPage ?? 605)
            : 605
        let totalPages = nextSurahStart - info.startPage
        guard totalPages > 0, info.ayahCount > 0 else { return info.startPage }

        // Proportional estimate within the surah's page range
        let fraction = Double(ref.ayah - 1) / Double(info.ayahCount)
        let estimated = info.startPage + Int(fraction * Double(totalPages))
        return min(max(estimated, info.startPage), nextSurahStart - 1)
    }

    /// Returns the primary surah on a given page.
    func surahOnPage(_ page: Int) -> SurahInfo? {
        // Find the surah whose startPage is <= page and is the closest
        var result: SurahInfo?
        for s in surahs {
            if s.startPage <= page {
                result = s
            } else {
                break
            }
        }
        return result
    }

    /// Returns the ayah after the given one, or nil if it's the last ayah.
    func ayah(after ref: AyahRef) -> AyahRef? {
        let count = ayahCount(surah: ref.surah)
        if ref.ayah < count {
            return AyahRef(surah: ref.surah, ayah: ref.ayah + 1)
        }
        // Move to next surah
        if ref.surah < 114 {
            return AyahRef(surah: ref.surah + 1, ayah: 1)
        }
        return nil
    }

    /// Returns the ayah before the given one, or nil if it's the first ayah.
    func ayah(before ref: AyahRef) -> AyahRef? {
        if ref.ayah > 1 {
            return AyahRef(surah: ref.surah, ayah: ref.ayah - 1)
        }
        // Move to previous surah
        if ref.surah > 1 {
            let prevCount = ayahCount(surah: ref.surah - 1)
            return AyahRef(surah: ref.surah - 1, ayah: prevCount)
        }
        return nil
    }

    func firstAyah(ofSurah surah: Int) -> AyahRef {
        AyahRef(surah: surah, ayah: 1)
    }

    var totalAyahCount: Int {
        surahs.reduce(0) { $0 + $1.ayahCount }
    }
}
