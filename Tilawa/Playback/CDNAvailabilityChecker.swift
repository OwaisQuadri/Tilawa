import Foundation

/// Probes a CDN reciter's full ayah list using HTTP HEAD requests to detect missing files.
/// Runs up to `maxConcurrency` requests in parallel.
actor CDNAvailabilityChecker {

    static let shared = CDNAvailabilityChecker()
    private init() {}

    private let maxConcurrency = 100
    private let metadata = QuranMetadataService.shared

    // MARK: - Public API

    /// Probes all 6236 ayahs and returns the ones confirmed absent on the CDN.
    ///
    /// - Parameters:
    ///   - reciter: The CDN reciter to check.
    ///   - progress: Called with 0.0–1.0 as checking proceeds (may be on any thread).
    /// - Returns: Array of `AyahRef` values that returned a non-200 or failed response.
    func findMissingAyahs(reciter: Reciter,
                          progress: @Sendable (Double) -> Void) async -> [AyahRef] {
        let refs = allAyahRefs()
        let total = refs.count
        var missing: [AyahRef] = []
        var completed = 0

        await withTaskGroup(of: (AyahRef, Bool).self) { group in
            var inflight = 0

            for ref in refs {
                if inflight >= maxConcurrency {
                    if let (checkedRef, isAvailable) = await group.next() {
                        if !isAvailable { missing.append(checkedRef) }
                        completed += 1
                        progress(Double(completed) / Double(total))
                        inflight -= 1
                    }
                }
                group.addTask {
                    let available = await Self.probe(ref: ref, reciter: reciter)
                    return (ref, available)
                }
                inflight += 1
            }

            // Drain remaining tasks
            for await (checkedRef, isAvailable) in group {
                if !isAvailable { missing.append(checkedRef) }
                completed += 1
                progress(Double(completed) / Double(total))
            }
        }

        return missing
    }

    // MARK: - Private

    /// All 6236 ayah refs in Quran order (Surah 1:1 → 114:last).
    private func allAyahRefs() -> [AyahRef] {
        (1...114).flatMap { surah in
            let count = metadata.ayahCount(surah: surah)
            return (1...max(1, count)).map { AyahRef(surah: surah, ayah: $0) }
        }
    }

    /// Sends a HEAD request for one ayah's CDN URL.
    /// Returns `true` if the server responds HTTP 200, `false` for any other result.
    private static func probe(ref: AyahRef, reciter: Reciter) async -> Bool {
        guard let url = await AudioFileCache.shared.remoteURL(for: ref, reciter: reciter) else {
            return false
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
