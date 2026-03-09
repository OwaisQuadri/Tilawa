import Foundation

/// Maps Hafs ayah references to native ayah numbers in other riwayat.
///
/// Different riwayat use different ayah-splitting conventions. For example:
/// - Hafs 1:1 (Basmala) has no independent equivalent in Warsh/Qaloon
/// - Hafs 1:2 (Al-Hamd) = Warsh 1:1
/// - Hafs 2:1+2:2 are merged into Warsh 2:1
///
/// The offset maps are derived from the KFGQPC dataset (6,214 native ayahs for
/// Warsh and Qaloon) using a Needleman-Wunsch global text alignment.
///
/// Data files: `Tilawa/Resources/QuranData/ayah_offset_maps/<riwayah>.json`
/// Format: `surahs[surahIndex][ayahIndex]` = native ayah number or null (0-based indices)
///
/// Riwayat with no offset file (e.g. Hafs, Shu'bah) use 1:1 identity mapping.
final class AyahOffsetService: @unchecked Sendable {

    static let shared = AyahOffsetService()

    // MARK: - Cache

    private let lock = NSLock()
    private var surahsCache: [Riwayah: [[Int?]]] = [:]    // riwayat with data
    private var identityRiwayat: Set<Riwayah> = []         // riwayat with no offset file → 1:1

    // MARK: - Public API

    /// Returns the native ayah number in `riwayah` that corresponds to the given Hafs ref.
    /// Returns `nil` if the Hafs position has no independent equivalent in that riwayah
    /// (e.g. the Basmala in Warsh surah 1, or merged ayahs).
    /// Returns the Hafs ayah number unchanged for riwayat with no offset data (identity mapping).
    func nativeAyah(for hafsRef: AyahRef, riwayah: Riwayah) -> Int? {
        guard riwayah != .hafs else { return hafsRef.ayah }

        guard let surahs = offsetSurahs(for: riwayah) else {
            return hafsRef.ayah   // identity mapping: no offset file for this riwayah
        }

        let surahIdx = hafsRef.surah - 1
        let ayahIdx  = hafsRef.ayah - 1
        guard surahIdx >= 0, surahIdx < surahs.count else { return hafsRef.ayah }
        let surah = surahs[surahIdx]
        guard ayahIdx >= 0, ayahIdx < surah.count else { return hafsRef.ayah }
        return surah[ayahIdx]   // nil means no native equivalent
    }

    /// Returns the native `AyahRef` in `riwayah` for a given Hafs ref, or `nil` if there
    /// is no independent equivalent in that riwayah.
    func nativeRef(for hafsRef: AyahRef, riwayah: Riwayah) -> AyahRef? {
        guard let native = nativeAyah(for: hafsRef, riwayah: riwayah) else { return nil }
        return AyahRef(surah: hafsRef.surah, ayah: native)
    }

    /// Returns whether a Hafs ayah has an independent equivalent in `riwayah`.
    func hasNativeEquivalent(_ hafsRef: AyahRef, riwayah: Riwayah) -> Bool {
        nativeAyah(for: hafsRef, riwayah: riwayah) != nil
    }

    // MARK: - Internal

    /// Returns the surahs offset table for `riwayah`, or `nil` if no file exists (identity mapping).
    private func offsetSurahs(for riwayah: Riwayah) -> [[Int?]]? {
        lock.lock()
        defer { lock.unlock() }

        if identityRiwayat.contains(riwayah) { return nil }
        if let cached = surahsCache[riwayah] { return cached }

        if let loaded = loadFile(named: riwayah.rawValue) {
            surahsCache[riwayah] = loaded
            return loaded
        } else {
            identityRiwayat.insert(riwayah)
            return nil
        }
    }

    private func loadFile(named name: String) -> [[Int?]]? {
        guard let url = Bundle.main.url(
            forResource: "ayah_offset_\(name)",
            withExtension: "json"
        ) else { return nil }

        guard let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(OffsetRoot.self, from: data) else {
            return nil
        }
        return root.surahs
    }
}

// MARK: - Decodable

private struct OffsetRoot: Decodable {
    let surahs: [[Int?]]
}
