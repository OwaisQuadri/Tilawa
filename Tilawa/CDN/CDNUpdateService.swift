import Foundation
import SwiftData

/// Checks CDN reciters for updates on first launch each day.
/// Compares manifest version numbers and re-runs availability checks per source.
/// Re-downloads previously cached surahs if new ayahs appear or content version changes.
@Observable
@MainActor
final class CDNUpdateService {

    static let shared = CDNUpdateService()
    private init() {}

    private static let lastCheckKey = "cdn.lastUpdateCheck"

    private(set) var isChecking = false

    /// Run once per day on app launch. Skips if already checked today.
    func checkForUpdatesIfNeeded(context: ModelContext) async {
        let now = Date()
        let lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date

        if let lastCheck, Calendar.current.isDate(lastCheck, inSameDayAs: now) {
            return // Already checked today
        }

        isChecking = true
        defer {
            isChecking = false
            UserDefaults.standard.set(now, forKey: Self.lastCheckKey)
        }

        let descriptor = FetchDescriptor<Reciter>()
        guard let reciters = try? context.fetch(descriptor) else { return }

        let cdnReciters = reciters.filter { $0.hasCDN }
        guard !cdnReciters.isEmpty else { return }

        for reciter in cdnReciters {
            guard let sources = reciter.cdnSources, !sources.isEmpty else { continue }

            let previouslyDownloaded = reciter.downloadedSurahs
            guard !previouslyDownloaded.isEmpty else { continue }

            for source in sources {
                let oldMissing = Set(source.missingAyahs)
                let oldVersion = source.cdnVersion

                // Check manifest for version change
                let remoteVersion = await fetchManifestVersion(for: source)
                let versionChanged = remoteVersion != nil && remoteVersion != oldVersion

                // Re-check availability
                let newMissing = await CDNAvailabilityChecker.shared.findMissingAyahs(
                    reciter: reciter,
                    source: source,
                    progress: { _ in }
                )

                // Persist updated availability on the source
                if let encoded = try? JSONEncoder().encode(newMissing),
                   let json = String(data: encoded, encoding: .utf8) {
                    source.missingAyahsJSON = json
                }
                if let remoteVersion {
                    source.cdnVersion = remoteVersion
                }
                try? context.save()

                // Determine which surahs need re-downloading
                let newMissingSet = Set(newMissing)
                let newlyAvailable = oldMissing.subtracting(newMissingSet)

                var surahsToUpdate: Set<Int>
                if versionChanged {
                    // Version changed — re-download all previously cached surahs
                    surahsToUpdate = Set(previouslyDownloaded)
                } else {
                    // Only re-download surahs with newly available ayahs
                    surahsToUpdate = Set(newlyAvailable.map(\.surah))
                        .intersection(previouslyDownloaded)
                }

                guard !surahsToUpdate.isEmpty else { continue }

                // Clear cache for affected surahs if version changed (files may have new content)
                if versionChanged {
                    await AudioFileCache.shared.deleteCache(for: reciter, source: source)
                }

                DownloadManager.shared.enqueue(
                    surahs: Array(surahsToUpdate).sorted(),
                    reciter: reciter,
                    source: source,
                    context: context
                )
            }
        }
    }

    // MARK: - Manifest version fetch

    /// Fetches the manifest JSON for a CDN source and returns the version number, or nil if unavailable.
    private func fetchManifestVersion(for source: ReciterCDNSource) async -> Int? {
        guard let folderId = source.cdnFolderId else { return nil }
        let manifestURL = "\(CDNUploadManager.workerBaseURL)/manifests/\(folderId).json"
        guard let url = URL(string: manifestURL) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let manifest = try JSONDecoder().decode(ManifestVersionResponse.self, from: data)
            return manifest.version
        } catch {
            return nil
        }
    }

    private struct ManifestVersionResponse: Codable {
        let version: Int?
    }
}
