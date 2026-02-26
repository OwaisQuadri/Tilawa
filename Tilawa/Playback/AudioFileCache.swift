import Foundation
import AVFoundation

/// Thread-safe cache for downloaded reciter audio files.
/// Files are stored in the app's Caches directory under a per-reciter subdirectory.
actor AudioFileCache {

    static let shared = AudioFileCache()

    private let fileManager = FileManager.default
    private var activeDownloads: Set<String> = []  // keys being downloaded

    // MARK: - URL Construction

    /// Returns the local cache URL for an ayah audio file (may not exist yet).
    func localFileURL(for ref: AyahRef, reciter: Reciter) -> URL {
        let cacheDir = cacheDirectory(for: reciter)
        let filename = audioFilename(for: ref, reciter: reciter)
        return cacheDir.appendingPathComponent(filename)
    }

    /// Returns the remote CDN URL for an ayah, or nil if the reciter has no CDN configured.
    func remoteURL(for ref: AyahRef, reciter: Reciter) -> URL? {
        if reciter.namingPattern == .urlTemplate {
            guard let template = reciter.audioURLTemplate else { return nil }
            let urlString = Self.substituteURLTemplate(template, surah: ref.surah, ayah: ref.ayah)
            return URL(string: urlString)
        }
        guard let base = reciter.remoteBaseURL,
              let baseURL = URL(string: base) else { return nil }
        let filename = audioFilename(for: ref, reciter: reciter)
        return baseURL.appendingPathComponent(filename)
    }

    // MARK: - Cache Checks

    func isFileCached(ref: AyahRef, reciter: Reciter) -> Bool {
        let url = localFileURL(for: ref, reciter: reciter)
        return fileManager.fileExists(atPath: url.path)
    }

    func isSurahFullyCached(_ surah: Int, reciter: Reciter,
                             metadata: QuranMetadataService) -> Bool {
        let count = metadata.ayahCount(surah: surah)
        guard count > 0 else { return false }
        return (1...count).allSatisfy { ayah in
            isFileCached(ref: AyahRef(surah: surah, ayah: ayah), reciter: reciter)
        }
    }

    // MARK: - Single File Download

    /// Downloads a single ayah's audio file. No-ops if already cached or downloading.
    func download(ref: AyahRef, reciter: Reciter) async throws {
        let key = cacheKey(ref: ref, reciter: reciter)
        guard !isFileCached(ref: ref, reciter: reciter),
              !activeDownloads.contains(key) else { return }

        guard let remoteURL = remoteURL(for: ref, reciter: reciter) else { return }

        activeDownloads.insert(key)
        defer { activeDownloads.remove(key) }

        let destURL = localFileURL(for: ref, reciter: reciter)
        try ensureCacheDirectoryExists(for: reciter)

        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        // Reject non-200 responses (e.g. 403 rate-limit or 404 returns HTML, not MP3)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? fileManager.removeItem(at: tempURL)
            throw URLError(.badServerResponse)
        }
        // Move from temp location to permanent cache
        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }
        try fileManager.moveItem(at: tempURL, to: destURL)
    }

    // MARK: - Surah Batch Download

    /// Downloads all ayaat in a surah concurrently (max 6 parallel tasks).
    /// Reports progress via the `progress` closure (0.0–1.0).
    func downloadSurah(_ surah: Int,
                       reciter: Reciter,
                       metadata: QuranMetadataService,
                       progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let count = metadata.ayahCount(surah: surah)
        guard count > 0 else { return }

        let refs = (1...count).map { AyahRef(surah: surah, ayah: $0) }
            .filter { !isFileCached(ref: $0, reciter: reciter) }

        guard !refs.isEmpty else {
            progress?(1.0)
            return
        }

        try ensureCacheDirectoryExists(for: reciter)

        var completed = 0
        let total = refs.count

        try await withThrowingTaskGroup(of: Void.self) { group in
            var inflight = 0
            for ref in refs {
                // Limit concurrency to 6
                if inflight >= 6 {
                    try await group.next()
                    completed += 1
                    progress?(Double(completed) / Double(total))
                    inflight -= 1
                }
                group.addTask { [weak self] in
                    guard let self else { return }
                    try await self.download(ref: ref, reciter: reciter)
                }
                inflight += 1
            }
            // Drain remaining
            for try await _ in group {
                completed += 1
                progress?(Double(completed) / Double(total))
            }
        }
    }

    // MARK: - Cache Management

    /// Deletes all cached files for a reciter.
    func deleteCache(for reciter: Reciter) throws {
        let dir = cacheDirectory(for: reciter)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        try fileManager.removeItem(at: dir)
    }

    /// Returns total bytes used by a reciter's cache.
    func cacheSize(for reciter: Reciter) -> Int64 {
        let dir = cacheDirectory(for: reciter)
        guard let enumerator = fileManager.enumerator(at: dir,
                                                       includingPropertiesForKeys: [.fileSizeKey],
                                                       options: .skipsHiddenFiles) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: - Audio Duration

    /// Loads the duration of a local audio file using AVURLAsset.
    func audioDuration(url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? seconds : nil
        } catch {
            return nil
        }
    }

    // MARK: - Private Helpers

    private func cacheDirectory(for reciter: Reciter) -> URL {
        let dirName = reciter.localCacheDirectory ?? reciter.id?.uuidString ?? "unknown"
        return cachesBaseURL().appendingPathComponent(dirName)
    }

    private func cachesBaseURL() -> URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TilawaAudio")
    }

    private func audioFilename(for ref: AyahRef, reciter: Reciter) -> String {
        let format = reciter.audioFileFormat ?? "mp3"
        switch reciter.namingPattern {
        case .surahAyah:
            let surah = String(format: "%03d", ref.surah)
            let ayah  = String(format: "%03d", ref.ayah)
            return "\(surah)\(ayah).\(format)"
        case .sequential:
            let index = sequentialIndex(for: ref)
            return "\(index).\(format)"
        case .urlTemplate:
            // Use surahAyah format for local cache filenames regardless of remote URL structure.
            let surah = String(format: "%03d", ref.surah)
            let ayah  = String(format: "%03d", ref.ayah)
            return "\(surah)\(ayah).\(format)"
        }
    }

    // MARK: - URL Template Substitution

    /// Substitutes ${s}, ${ss}, ${sss} (surah) and ${a}, ${aa}, ${aaa} (ayah) tokens.
    /// Longer tokens are replaced first to avoid partial matches (${sss} before ${ss} before ${s}).
    static func substituteURLTemplate(_ template: String, surah: Int, ayah: Int) -> String {
        var result = template
        // Surah tokens (longest first)
        result = result.replacingOccurrences(of: "${sss}", with: String(format: "%03d", surah))
        result = result.replacingOccurrences(of: "${ss}",  with: String(format: "%02d", surah))
        result = result.replacingOccurrences(of: "${s}",   with: "\(surah)")
        // Ayah tokens (longest first)
        result = result.replacingOccurrences(of: "${aaa}", with: String(format: "%03d", ayah))
        result = result.replacingOccurrences(of: "${aa}",  with: String(format: "%02d", ayah))
        result = result.replacingOccurrences(of: "${a}",   with: "\(ayah)")
        return result
    }

    /// Computes the 1-based sequential ayah index (1–6236) across the whole Quran.
    private func sequentialIndex(for ref: AyahRef) -> Int {
        let metadata = QuranMetadataService.shared
        var index = 0
        for surah in 1..<ref.surah {
            index += metadata.ayahCount(surah: surah)
        }
        return index + ref.ayah
    }

    private func cacheKey(ref: AyahRef, reciter: Reciter) -> String {
        "\(reciter.id?.uuidString ?? "?")_\(ref.surah)_\(ref.ayah)"
    }

    private func ensureCacheDirectoryExists(for reciter: Reciter) throws {
        let dir = cacheDirectory(for: reciter)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir,
                                            withIntermediateDirectories: true)
        }
    }
}
