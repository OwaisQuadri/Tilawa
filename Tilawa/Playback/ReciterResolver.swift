import Foundation
import AVFoundation

/// Resolves the best available AyahAudioItem for a given ayah ref and session snapshot.
///
/// Resolution order (per priority entry, in list order):
///   1. Riwayah gate — personal segments use the recording's own riwayah (overrides reciter's);
///      CDN sources use the reciter's riwayah.
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
        // Check if a segment override covers this ayah; use its priority list if so
        let matchingOverride = snapshot.segmentOverrides.first { $0.range.contains(ref) }
        let priorityList = matchingOverride.map(\.reciterPriority) ?? snapshot.reciterPriority

        for entry in priorityList {
            let reciter = entry.reciter

            // Build unified source priority list
            struct SourceAttempt {
                let effectiveOrder: Int
                let tiebreaker: Int   // personal=0, cdnManifest=1, cdnTemplate=2
                let subRank: Int
                let resolve: () async -> AyahAudioItem?
            }

            var attempts: [SourceAttempt] = []

            // Personal segments — riwayah gate uses the recording's own riwayah,
            // falling back to the reciter's riwayah for recordings that predate the field.
            let allSegments = await libraryService.segments(for: ref, reciter: reciter)
            let sortedSegments = allSegments.sorted { lhs, rhs in
                let lhsOrder = lhs.userSortOrder
                let rhsOrder = rhs.userSortOrder
                if let lo = lhsOrder, let ro = rhsOrder, lo != ro { return lo < ro }
                if lhsOrder != nil && rhsOrder == nil { return true }
                if lhsOrder == nil && rhsOrder != nil { return false }
                let lhsManual = lhs.isManuallyAnnotated ?? false
                let rhsManual = rhs.isManuallyAnnotated ?? false
                if lhsManual != rhsManual { return lhsManual }
                if (lhs.confidenceScore ?? 0) != (rhs.confidenceScore ?? 0) {
                    return (lhs.confidenceScore ?? 0) > (rhs.confidenceScore ?? 0)
                }
                let lhsDate = lhs.recording?.importedAt ?? .distantPast
                let rhsDate = rhs.recording?.importedAt ?? .distantPast
                return lhsDate > rhsDate
            }

            for (rank, seg) in sortedSegments.enumerated() {
                attempts.append(SourceAttempt(
                    effectiveOrder: seg.userSortOrder ?? Int.max,
                    tiebreaker: 0,
                    subRank: rank,
                    resolve: { [weak self] in
                        let segRiwayah = seg.recording?.safeRiwayah ?? reciter.safeRiwayah
                        guard segRiwayah == snapshot.riwayah else { return nil }
                        return await self?.resolveSegmentItem(seg, ref: ref)
                    }
                ))
            }

            // CDN manifest — gate on reciter's riwayah (CDN is always one riwayah)
            if reciter.remoteBaseURL != nil {
                attempts.append(SourceAttempt(
                    effectiveOrder: reciter.cdnManifestOrder ?? Int.max,
                    tiebreaker: 1,
                    subRank: 0,
                    resolve: { [weak self] in
                        guard reciter.safeRiwayah == snapshot.riwayah else { return nil }
                        return await self?.resolveCDN(ref: ref, reciter: reciter)
                    }
                ))
            }

            // CDN url template — gate on reciter's riwayah
            if reciter.audioURLTemplate != nil {
                attempts.append(SourceAttempt(
                    effectiveOrder: reciter.cdnTemplateOrder ?? Int.max,
                    tiebreaker: 2,
                    subRank: 0,
                    resolve: { [weak self] in
                        guard reciter.safeRiwayah == snapshot.riwayah else { return nil }
                        return await self?.resolveCDN(ref: ref, reciter: reciter)
                    }
                ))
            }

            attempts.sort {
                if $0.effectiveOrder != $1.effectiveOrder { return $0.effectiveOrder < $1.effectiveOrder }
                if $0.tiebreaker != $1.tiebreaker { return $0.tiebreaker < $1.tiebreaker }
                return $0.subRank < $1.subRank
            }

            for attempt in attempts {
                if let item = await attempt.resolve() { return item }
            }
        }
        return nil
    }

    // MARK: - Personal Recording Resolution

    private func resolveSegmentItem(_ seg: RecordingSegment, ref: AyahRef) async -> AyahAudioItem? {
        guard let recording = seg.recording,
              let path = recording.storagePath,
              let url = ubiquityURL(for: path) else { return nil }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let duration = await cache.audioDuration(url: url) ?? recording.safeDuration
        let endAyahRef = AyahRef(surah: seg.endSurahNumber ?? ref.surah,
                                  ayah:  seg.endAyahNumber  ?? ref.ayah)
        return AyahAudioItem(
            id: UUID(),
            ayahRef: ref,
            endAyahRef: endAyahRef,
            audioURL: url,
            startOffset: seg.startOffsetSeconds ?? 0,
            endOffset: seg.endOffsetSeconds ?? duration,
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
            endAyahRef: ref,   // CDN files are always single-ayah
            audioURL: localURL,
            startOffset: 0,
            endOffset: duration,
            reciterName: reciter.safeName,
            reciterId: reciter.id ?? UUID(),
            isPersonalRecording: false
        )
    }

    // MARK: - Local storage

    /// Returns the local Documents URL for a recording storage path.
    /// Audio files are stored in Documents/TilawaRecordings/.
    /// iCloud Drive (ubiquity container) sync is deferred — it requires the
    /// com.apple.developer.ubiquity-container-identifiers entitlement in addition to CloudKit.
    private func ubiquityURL(for storagePath: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TilawaRecordings")
            .appendingPathComponent(storagePath)
    }
}
