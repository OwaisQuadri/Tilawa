import Foundation
import AVFoundation

/// Resolves the best available AyahAudioItem for a given ayah ref and session snapshot.
///
/// Resolution order (per priority entry, in list order):
///   1. Strict riwayah gate — skip if reciter's riwayah ≠ session riwayah
///   2. Personal recordings for this reciter (via RecordingLibraryService)
///   3. CDN local cache (via AudioFileCache)
///
/// Returns nil if no audio is available → engine produces a silence gap.
final class ReciterResolver {

    private let libraryService: any RecordingLibraryService
    private let cache: AudioFileCache

    init(libraryService: any RecordingLibraryService = StubRecordingLibraryService(),
         cache: AudioFileCache = .shared) {
        self.libraryService = libraryService
        self.cache = cache
    }

    func resolve(ref: AyahRef,
                 snapshot: PlaybackSettingsSnapshot) async -> AyahAudioItem? {
        for entry in snapshot.reciterPriority {
            let reciter = entry.reciter

            // Strict riwayah gate
            guard reciter.safeRiwayah == snapshot.riwayah else { continue }

            // Step 1: personal recordings
            if let item = await resolvePersonalRecording(ref: ref, reciter: reciter) {
                return item
            }

            // Step 2: CDN local cache
            let localURL = await cache.localFileURL(for: ref, reciter: reciter)
            print("   📁 \(localURL.lastPathComponent) exists=\(FileManager.default.fileExists(atPath: localURL.path))")
            if let item = await resolveCDN(ref: ref, reciter: reciter) {
                return item
            }
        }
        return nil
    }

    // MARK: - Personal Recording Resolution

    private func resolvePersonalRecording(ref: AyahRef,
                                           reciter: Reciter) async -> AyahAudioItem? {
        let allSegments = await libraryService.segments(for: ref, reciter: reciter)
        let sorted = allSegments.sorted {
            let lhsManual = $0.isManuallyAnnotated ?? false
            let rhsManual = $1.isManuallyAnnotated ?? false
            if lhsManual != rhsManual { return lhsManual }
            return ($0.confidenceScore ?? 0) > ($1.confidenceScore ?? 0)
        }

        guard let best = sorted.first,
              let recording = best.recording,
              let path = recording.storagePath,
              let url = ubiquityURL(for: path) else { return nil }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let duration = await cache.audioDuration(url: url) ?? recording.safeDuration
        return AyahAudioItem(
            id: UUID(),
            ayahRef: ref,
            audioURL: url,
            startOffset: best.startOffsetSeconds ?? 0,
            endOffset: best.endOffsetSeconds ?? duration,
            reciterName: recording.reciter?.safeName ?? "Personal Recording",
            reciterId: recording.reciter?.id ?? UUID(),
            isPersonalRecording: true
        )
    }

    // MARK: - CDN Resolution

    private func resolveCDN(ref: AyahRef, reciter: Reciter) async -> AyahAudioItem? {
        let localURL = await cache.localFileURL(for: ref, reciter: reciter)

        if !FileManager.default.fileExists(atPath: localURL.path) {
            let remoteURL = await cache.remoteURL(for: ref, reciter: reciter)
            print("   ⬇️ \(localURL.lastPathComponent) not cached — downloading from \(remoteURL?.absoluteString ?? "nil")")
            do {
                try await cache.download(ref: ref, reciter: reciter)
                print("   ✅ Downloaded \(localURL.lastPathComponent)")
            } catch {
                print("   ❌ Download failed \(localURL.lastPathComponent): \(error.localizedDescription)")
                return nil
            }
        }

        guard FileManager.default.fileExists(atPath: localURL.path) else { return nil }

        let duration = await cache.audioDuration(url: localURL) ?? 0
        return AyahAudioItem(
            id: UUID(),
            ayahRef: ref,
            audioURL: localURL,
            startOffset: 0,
            endOffset: duration,
            reciterName: reciter.safeName,
            reciterId: reciter.id ?? UUID(),
            isPersonalRecording: false
        )
    }

    // MARK: - iCloud (deferred)

    /// Returns the ubiquity container URL for a storage path, or nil if iCloud is not set up.
    private func ubiquityURL(for storagePath: String) -> URL? {
        // iCloud container setup is deferred until CloudKit entitlements are added.
        // Once entitlements are in place, replace with:
        //   FileManager.default.url(forUbiquityContainerIdentifier: nil)?
        //       .appendingPathComponent(storagePath)
        return nil
    }
}
