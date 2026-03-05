import Foundation

/// Provides O(1) riwayah compatibility lookup for a given (surah, ayah) position.
///
/// For each position, the bundled JSON defines compatibility groups — sets of riwayaat
/// whose Quranic text is equivalent at that ayah. When resolving audio, a personal
/// segment whose riwayah is in the same group as the target riwayah can be used without
/// violating textual integrity.
///
/// If an ayah has no entry in the JSON, only strict (exact) matching applies —
/// a segment is only accepted when its riwayah exactly equals the target riwayah.
final class RiwayahCompatibilityService {

    static let shared = RiwayahCompatibilityService()

    // Keyed by surah * 10_000 + ayah  (supports up to 9999 ayahs per surah)
    private var table: [Int: [[Riwayah]]] = [:]
    private var isLoaded = false
    private let lock = NSLock()
    // Cache for everCompatible(with:) — only written on main thread
    private var everCompatibleCache: [Riwayah: Set<Riwayah>] = [:]

    private init() {}

    // MARK: - Public API

    /// Returns all riwayaat that are compatible with `targetRiwayah` at the given position.
    /// Always includes `targetRiwayah` itself.
    /// Falls back to `[targetRiwayah]` (strict) if no entry exists for this ayah.
    func compatibleRiwayaat(surah: Int, ayah: Int, targetRiwayah: Riwayah) -> Set<Riwayah> {
        ensureLoaded()
        let key = surah * 10_000 + ayah
        guard let groups = table[key] else { return [targetRiwayah] }
        for group in groups where group.contains(targetRiwayah) {
            return Set(group)
        }
        return [targetRiwayah]
    }

    /// Returns all riwayaat that share a compatibility group with `riwayah` for at least one
    /// ayah in the loaded table. Always includes `riwayah` itself. Result is cached.
    /// Intended for main-thread use only (PlaybackSetupSheet helpers).
    func everCompatible(with riwayah: Riwayah) -> Set<Riwayah> {
        if let cached = everCompatibleCache[riwayah] { return cached }
        ensureLoaded()
        var result: Set<Riwayah> = [riwayah]
        for groups in table.values {
            for group in groups where group.contains(riwayah) {
                result.formUnion(group)
            }
        }
        everCompatibleCache[riwayah] = result
        return result
    }

    // MARK: - Lazy loading

    private func ensureLoaded() {
        lock.lock(); defer { lock.unlock() }
        guard !isLoaded else { return }
        isLoaded = true

        guard let url = Bundle.main.url(forResource: "riwayah_compatibility", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([CompatibilityEntry].self, from: data)
        else { return }

        for entry in entries {
            let key = entry.surah * 10_000 + entry.ayah
            table[key] = entry.groups.map { $0.compactMap { Riwayah(rawValue: $0) } }.filter { !$0.isEmpty }
        }
    }

    // MARK: - JSON model

    private struct CompatibilityEntry: Decodable {
        let surah: Int
        let ayah: Int
        /// Each inner array is one compatibility group (riwayaat with identical text at this position).
        let groups: [[String]]
    }
}
