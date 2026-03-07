import Foundation
import AVFoundation

/// Resolves the best available AyahAudioItem for a given ayah ref and session snapshot.
///
/// Resolution order (per priority entry, in list order):
///   1. Riwayah gate — personal segments use the segment's own riwayah;
///      CDN sources use the source's riwayah.
///   2. Personal recordings for this reciter (via RecordingLibraryService)
///   3. CDN sources (one SourceAttempt per ReciterCDNSource, ordered by sortOrder)
///
/// Returns nil if no audio is available → engine produces a silence gap.
final class ReciterResolver {

    private let libraryService: any RecordingLibraryService
    private let cache: AudioFileCache
    private let compatibilityService: RiwayahCompatibilityService
    private let metadata = QuranMetadataService.shared

    init(libraryService: any RecordingLibraryService = StubRecordingLibraryService(),
         cache: AudioFileCache = .shared,
         compatibilityService: RiwayahCompatibilityService = .shared) {
        self.libraryService = libraryService
        self.cache = cache
        self.compatibilityService = compatibilityService
    }

    func resolve(ref: AyahRef,
                 snapshot: PlaybackSettingsSnapshot,
                 rangeBound: AyahRef? = nil) async -> AyahAudioItem? {
        let matchingOverride = snapshot.segmentOverrides.first { $0.range.contains(ref) }
        let priorityList = matchingOverride.map(\.reciterPriority) ?? snapshot.reciterPriority

        for entry in priorityList {
            let reciter = entry.reciter

            struct SourceAttempt {
                let effectiveOrder: Int
                let tiebreaker: Int   // personalExact=0, personalCompatible=1, cdnManifest=2, cdnTemplate=3
                let subRank: Int
                let resolve: () async -> AyahAudioItem?
            }

            var attempts: [SourceAttempt] = []

            // Personal segments — gate on segment's own riwayah
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

            // Pre-compute compatible riwayaat for this ref — used for both personal and CDN.
            let compatibles = compatibilityService.compatibleRiwayaat(
                surah: ref.surah, ayah: ref.ayah, targetRiwayah: snapshot.riwayah)

            for (rank, seg) in sortedSegments.enumerated() {
                let isExact = seg.safeRiwayah == snapshot.riwayah
                guard compatibles.contains(seg.safeRiwayah) else { continue }
                // Skip multi-ayah segments whose end extends past the playback range.
                let segEnd = AyahRef(surah: seg.endSurahNumber ?? ref.surah,
                                     ayah:  seg.endAyahNumber  ?? ref.ayah)
                if let bound = rangeBound, segEnd > bound { continue }
                // For compatible (non-exact) segments, verify compatibility holds for every ayah
                // in the segment range — the engine plays the segment audio across the full range.
                if !isExact {
                    let segStart = AyahRef(surah: seg.surahNumber    ?? ref.surah,
                                           ayah:  seg.ayahNumber     ?? ref.ayah)
                    guard isCompatibleAcrossRange(segRiwayah: seg.safeRiwayah,
                                                  targetRiwayah: snapshot.riwayah,
                                                  from: segStart, to: segEnd) else { continue }
                }
                attempts.append(SourceAttempt(
                    effectiveOrder: seg.userSortOrder ?? Int.max,
                    tiebreaker: isExact ? 0 : 1,
                    subRank: rank,
                    resolve: { [weak self] in
                        return await self?.resolveSegmentItem(seg, ref: ref)
                    }
                ))
            }

            // CDN sources — gate on compatibility (exact = tiebreaker 2/3; compatible = 4/5).
            for (idx, source) in (reciter.cdnSources ?? []).enumerated() {
                guard let raw = source.riwayah,
                      let sourceRiwayah = Riwayah(rawValue: raw),
                      compatibles.contains(sourceRiwayah) else { continue }
                let isExact = sourceRiwayah == snapshot.riwayah
                let tiebreaker: Int
                if isExact {
                    tiebreaker = source.urlTemplate != nil ? 3 : 2
                } else {
                    tiebreaker = source.urlTemplate != nil ? 5 : 4
                }
                attempts.append(SourceAttempt(
                    effectiveOrder: source.sortOrder ?? Int.max,
                    tiebreaker: tiebreaker,
                    subRank: idx,
                    resolve: { [weak self] in
                        return await self?.resolveCDN(ref: ref, reciter: reciter, source: source)
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
            reciterName: seg.reciter?.safeName ?? "Personal Recording",
            reciterId: seg.reciter?.id ?? UUID(),
            isPersonalRecording: true
        )
    }

    // MARK: - CDN Resolution

    private func resolveCDN(ref: AyahRef, reciter: Reciter, source: ReciterCDNSource) async -> AyahAudioItem? {
        let localURL = await cache.localFileURL(for: ref, reciter: reciter, source: source)

        if !FileManager.default.fileExists(atPath: localURL.path) {
            if await cache.isMissing404(ref: ref, reciter: reciter) { return nil }

            let remoteURL = await cache.remoteURL(for: ref, source: source)
            print("   ⬇️ \(localURL.lastPathComponent) not cached — downloading from \(remoteURL?.absoluteString ?? "nil")")
            do {
                try await cache.download(ref: ref, reciter: reciter, source: source)
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
            endAyahRef: ref,
            audioURL: localURL,
            startOffset: 0,
            endOffset: duration,
            reciterName: reciter.safeName,
            reciterId: reciter.id ?? UUID(),
            isPersonalRecording: false
        )
    }

    // MARK: - Range compatibility

    /// Returns true if `segRiwayah` is compatible with `targetRiwayah` at every ayah from
    /// `start` through `end` (inclusive). Short-circuits on the first incompatible ayah.
    private func isCompatibleAcrossRange(segRiwayah: Riwayah,
                                          targetRiwayah: Riwayah,
                                          from start: AyahRef,
                                          to end: AyahRef) -> Bool {
        var current = start
        while current <= end {
            let compatibles = compatibilityService.compatibleRiwayaat(
                surah: current.surah, ayah: current.ayah, targetRiwayah: targetRiwayah)
            if !compatibles.contains(segRiwayah) { return false }
            let count = metadata.ayahCount(surah: current.surah)
            if current.ayah < count {
                current = AyahRef(surah: current.surah, ayah: current.ayah + 1)
            } else if current.surah < 114 {
                current = AyahRef(surah: current.surah + 1, ayah: 1)
            } else { break }
        }
        return true
    }

    // MARK: - Local storage

    private func ubiquityURL(for storagePath: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TilawaRecordings")
            .appendingPathComponent(storagePath)
    }
}
