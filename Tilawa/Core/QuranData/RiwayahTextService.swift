import Foundation

/// Provides ayah-level Arabic text for each supported riwayah.
///
/// Text is loaded lazily per riwayah from bundled JSON files in
/// `Tilawa/Resources/QuranData/riwayah_text/<riwayah>.json`.
///
/// The JSON format is:
/// ```json
/// { "riwayah": "warsh", "total_ayahs": 6236, "surahs": [["ayah1", "ayah2", ...], ...] }
/// ```
/// where `surahs[surahIndex][ayahIndex]` uses 0-based indices
/// (surah 1 = index 0, ayah 1 = index 0).
///
/// Falls back to Hafs text if no file exists for the requested riwayah.
final class RiwayahTextService: @unchecked Sendable {

    static let shared = RiwayahTextService()

    // MARK: - Private State

    private let lock = NSLock()
    private var cache: [Riwayah: [[String]]] = [:]

    // MARK: - Public API

    /// Returns the Arabic text for a specific ayah in the given riwayah.
    /// Returns `nil` if the ayah reference is out of range.
    func text(for ref: AyahRef, riwayah: Riwayah) -> String? {
        let surahs = surahsData(for: riwayah)
        let surahIndex = ref.surah - 1
        let ayahIndex = ref.ayah - 1
        guard surahIndex >= 0, surahIndex < surahs.count else { return nil }
        let ayahs = surahs[surahIndex]
        guard ayahIndex >= 0, ayahIndex < ayahs.count else { return nil }
        return ayahs[ayahIndex]
    }

    /// Returns the total ayah count for a given surah in the given riwayah.
    func ayahCount(surah: Int, riwayah: Riwayah) -> Int? {
        let surahs = surahsData(for: riwayah)
        guard surah >= 1, surah <= surahs.count else { return nil }
        return surahs[surah - 1].count
    }

    /// Returns all ayahs for a given surah in the given riwayah.
    func ayahs(surah: Int, riwayah: Riwayah) -> [String] {
        let surahs = surahsData(for: riwayah)
        guard surah >= 1, surah <= surahs.count else { return [] }
        return surahs[surah - 1]
    }

    // MARK: - Internal

    private func surahsData(for riwayah: Riwayah) -> [[String]] {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[riwayah] { return cached }

        let loaded = load(riwayah: riwayah)
        cache[riwayah] = loaded
        return loaded
    }

    private func load(riwayah: Riwayah) -> [[String]] {
        // Try to load riwayah-specific file first
        if let data = loadFile(named: riwayah.rawValue) {
            return data
        }
        // Fall back to Hafs if specific riwayah file not bundled
        if riwayah != .hafs, let fallback = loadFile(named: Riwayah.hafs.rawValue) {
            return fallback
        }
        return []
    }

    private func loadFile(named name: String) -> [[String]]? {
        guard let url = Bundle.main.url(
            forResource: "riwayah_text_\(name)",
            withExtension: "json"
        ) else { return nil }

        guard let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(RiwayahTextRoot.self, from: data) else {
            return nil
        }
        return root.surahs
    }
}

// MARK: - Decodable Model

private struct RiwayahTextRoot: Decodable {
    let riwayah: String
    let surahs: [[String]]
}
