import Foundation

/// Provides riwayah-specific Quran structural metadata: ayah counts and surah start pages.
///
/// Different riwayat have different ayah-splitting conventions. For example, Warsh
/// and Qaloon have 6,214 total ayahs (vs Hafs's 6,236) because 50 surahs split
/// differently. The mushaf page layout (604 pages, same surah start pages) is
/// shared across Hafs, Warsh, and Qaloon.
///
/// Data is loaded lazily per riwayah from bundled JSON files at
/// `Tilawa/Resources/QuranData/riwayah_metadata/<riwayah>.json`.
/// Falls back to Hafs data for riwayat that don't have their own metadata file.
final class RiwayahMetadataService: @unchecked Sendable {

    static let shared = RiwayahMetadataService()

    // MARK: - Cache

    private let lock = NSLock()
    private var cache: [Riwayah: RiwayahMeta] = [:]

    // MARK: - Public API

    /// Returns the ayah count for a surah in the given riwayah.
    func ayahCount(surah: Int, riwayah: Riwayah) -> Int {
        guard let meta = surahMeta(surah, riwayah: riwayah) else {
            return QuranMetadataService.shared.ayahCount(surah: surah)
        }
        return meta.ayahCount
    }

    /// Returns the starting mushaf page for a surah in the given riwayah.
    func startPage(surah: Int, riwayah: Riwayah) -> Int {
        guard let meta = surahMeta(surah, riwayah: riwayah) else {
            return QuranMetadataService.shared.surah(surah)?.startPage ?? 1
        }
        return meta.startPage
    }

    /// Returns the total ayah count across all surahs for the given riwayah.
    func totalAyahCount(riwayah: Riwayah) -> Int {
        loadedMeta(for: riwayah).totalAyahs
    }

    /// Returns the total mushaf page count for the given riwayah.
    func totalPages(riwayah: Riwayah) -> Int {
        loadedMeta(for: riwayah).totalPages
    }

    // MARK: - Private

    private func surahMeta(_ surah: Int, riwayah: Riwayah) -> SurahMeta? {
        let meta = loadedMeta(for: riwayah)
        guard surah >= 1, surah <= meta.surahs.count else { return nil }
        return meta.surahs[surah - 1]
    }

    private func loadedMeta(for riwayah: Riwayah) -> RiwayahMeta {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[riwayah] { return cached }

        let loaded = load(riwayah: riwayah)
        cache[riwayah] = loaded
        return loaded
    }

    private func load(riwayah: Riwayah) -> RiwayahMeta {
        if let meta = loadFile(named: riwayah.rawValue) { return meta }
        // Fall back to Hafs
        if riwayah != .hafs, let fallback = loadFile(named: Riwayah.hafs.rawValue) {
            return fallback
        }
        // Last resort: build from QuranMetadataService
        return buildFromQuranMetadata()
    }

    private func loadFile(named name: String) -> RiwayahMeta? {
        guard let url = Bundle.main.url(
            forResource: "riwayah_metadata_\(name)",
            withExtension: "json",
            subdirectory: "QuranData/riwayah_metadata"
        ) else { return nil }

        guard let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(RiwayahMetaRoot.self, from: data) else {
            return nil
        }
        return root.toModel()
    }

    private func buildFromQuranMetadata() -> RiwayahMeta {
        let md = QuranMetadataService.shared
        let surahs = md.surahs.map { s in
            SurahMeta(number: s.number, ayahCount: s.ayahCount, startPage: s.startPage)
        }
        return RiwayahMeta(
            totalPages: 604,
            totalAyahs: md.totalAyahCount,
            surahs: surahs
        )
    }
}

// MARK: - Internal Models

struct RiwayahMeta: Sendable {
    let totalPages: Int
    let totalAyahs: Int
    let surahs: [SurahMeta]          // 114 entries, index 0 = surah 1
}

struct SurahMeta: Sendable {
    let number: Int
    let ayahCount: Int
    let startPage: Int
}

// MARK: - Decodable

private struct RiwayahMetaRoot: Decodable {
    let totalPages: Int
    let totalAyahs: Int
    let surahs: [SurahMetaRaw]

    func toModel() -> RiwayahMeta {
        RiwayahMeta(
            totalPages: totalPages,
            totalAyahs: totalAyahs,
            surahs: surahs.map { SurahMeta(number: $0.number, ayahCount: $0.ayahCount, startPage: $0.startPage) }
        )
    }
}

private struct SurahMetaRaw: Decodable {
    let number: Int
    let ayahCount: Int
    let startPage: Int
}
