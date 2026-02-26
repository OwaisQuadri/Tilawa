import Foundation

/// Provides exact ayah-based boundaries for the 240 rub' al-hizb (thumun) divisions,
/// derived from the QUL rub-metadata.json bundled with the app.
///
/// Each rub corresponds to one entry in JuzService.thumunStartPages:
///   rub N (1-indexed) ↔ thumunStartPages[N-1] (page where it starts)
final class RubService: Sendable {
    static let shared = RubService()

    struct RubEntry: Sendable {
        let rubNumber: Int       // 1–240
        let firstAyah: AyahRef  // exact first ayah (from first_verse_key)
        let lastAyah: AyahRef   // exact last ayah  (from last_verse_key)
        let versesCount: Int
    }

    /// All 240 rubs in Quran order (index 0 = rub 1).
    let rubs: [RubEntry]

    init() {
        guard let url  = Bundle.main.url(forResource: "rub-metadata", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw  = try? JSONDecoder().decode([String: RubJSON].self, from: data) else {
            self.rubs = []
            return
        }
        self.rubs = (1...240).compactMap { i -> RubEntry? in
            guard let j = raw["\(i)"] else { return nil }
            return RubEntry(
                rubNumber:   j.rub_number,
                firstAyah:   Self.parseKey(j.first_verse_key),
                lastAyah:    Self.parseKey(j.last_verse_key),
                versesCount: j.verses_count
            )
        }
    }

    // MARK: - Private JSON shape

    private struct RubJSON: Codable {
        let rub_number: Int
        let verses_count: Int
        let first_verse_key: String
        let last_verse_key: String
    }

    private static func parseKey(_ key: String) -> AyahRef {
        let parts = key.split(separator: ":").compactMap { Int($0) }
        return AyahRef(surah: parts[0], ayah: parts[1])
    }

    // MARK: - Ayah boundaries

    /// Exact first ayah of rub N (1-based).
    func firstAyah(ofRub rub: Int) -> AyahRef? {
        guard rub >= 1, rub <= rubs.count else { return nil }
        return rubs[rub - 1].firstAyah
    }

    /// Exact last ayah of rub N (1-based).
    func lastAyah(ofRub rub: Int) -> AyahRef? {
        guard rub >= 1, rub <= rubs.count else { return nil }
        return rubs[rub - 1].lastAyah
    }

    /// Rub range (first…last, inclusive, 1-based) for hizb N (1-60).
    func rubRange(ofHizb hizb: Int) -> ClosedRange<Int> {
        let first = (hizb - 1) * 4 + 1
        return first...(first + 3)
    }

    /// Rub range (first…last, inclusive, 1-based) for juz N (1-30).
    func rubRange(ofJuz juz: Int) -> ClosedRange<Int> {
        let first = (juz - 1) * 8 + 1
        return first...(first + 7)
    }

    // MARK: - Rub lookup for an ayah

    /// Returns the rub number (1-240) whose range contains the given ayah.
    func rubNumber(for ref: AyahRef) -> Int {
        let key = Self.ayahKey(ref)
        var lo = 0, hi = rubs.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if Self.ayahKey(rubs[mid].firstAyah) <= key { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1  // 1-indexed
    }

    // MARK: - Improved page estimation

    /// Page estimate using rub-level interpolation — significantly more accurate than
    /// surah-level proportional estimation (typically ±0-1 page vs. ±2 pages).
    func estimatedPage(for ref: AyahRef, metadata: QuranMetadataService) -> Int {
        guard !rubs.isEmpty else { return fallbackPage(for: ref, metadata: metadata) }

        let rubIdx = rubNumber(for: ref) - 1  // 0-indexed
        guard rubIdx < rubs.count,
              rubIdx < JuzService.thumunStartPages.count else {
            return fallbackPage(for: ref, metadata: metadata)
        }

        let entry     = rubs[rubIdx]
        let startPage = JuzService.thumunStartPages[rubIdx]
        let endPage   = rubIdx + 1 < JuzService.thumunStartPages.count
            ? JuzService.thumunStartPages[rubIdx + 1] - 1
            : 604

        guard startPage < endPage else { return startPage }

        let offset   = ayahOffset(of: ref, from: entry.firstAyah, metadata: metadata)
        let fraction = Double(offset) / Double(max(1, entry.versesCount))
        let page     = startPage + Int(fraction * Double(endPage - startPage + 1))
        return min(max(page, startPage), endPage)
    }

    // MARK: - Helpers

    static func ayahKey(_ ref: AyahRef) -> Int { ref.surah * 10000 + ref.ayah }

    /// Returns true if ref is within the closed range [first, last] in Quran order.
    static func ayah(_ ref: AyahRef, isBetween first: AyahRef, and last: AyahRef) -> Bool {
        let k = ayahKey(ref)
        return k >= ayahKey(first) && k <= ayahKey(last)
    }

    private func ayahOffset(of ref: AyahRef,
                             from start: AyahRef,
                             metadata: QuranMetadataService) -> Int {
        if ref.surah == start.surah {
            return ref.ayah - start.ayah
        }
        var offset = metadata.ayahCount(surah: start.surah) - start.ayah + 1
        for s in (start.surah + 1)..<ref.surah {
            offset += metadata.ayahCount(surah: s)
        }
        offset += ref.ayah - 1
        return offset
    }

    private func fallbackPage(for ref: AyahRef, metadata: QuranMetadataService) -> Int {
        guard let info = metadata.surah(ref.surah) else { return 1 }
        let nextStart = ref.surah < 114 ? (metadata.surah(ref.surah + 1)?.startPage ?? 605) : 605
        let totalPages = nextStart - info.startPage
        guard totalPages > 0, info.ayahCount > 0 else { return info.startPage }
        let fraction = Double(ref.ayah - 1) / Double(info.ayahCount)
        return info.startPage + min(Int(fraction * Double(totalPages)), totalPages - 1)
    }
}
