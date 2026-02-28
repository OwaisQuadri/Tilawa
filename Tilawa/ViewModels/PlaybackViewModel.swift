import Observation
import Foundation
import SwiftData

/// Thin @Observable wrapper around PlaybackEngine.
/// Consumed by SwiftUI views for playback controls and state display.
@Observable
final class PlaybackViewModel {

    let engine: PlaybackEngine
    private let metadata: QuranMetadataService

    // MARK: - Forwarded state (convenience accessors)

    var state: PlaybackState { engine.state }
    var currentAyah: AyahRef? { engine.currentAyah }
    var currentAyahEnd: AyahRef? { engine.currentAyahEnd }
    var currentReciterName: String { engine.currentReciterName }
    var currentAyahRepetition: Int { engine.currentAyahRepetition }
    var totalAyahRepetitions: Int { engine.totalAyahRepetitions }
    var currentRangeRepetition: Int { engine.currentRangeRepetition }
    var totalRangeRepetitions: Int { engine.totalRangeRepetitions }
    var isPlaying: Bool { engine.state == .playing }
    var unavailableAyah: AyahRef? { engine.unavailableAyah }
    var activeRange: AyahRange? { engine.activeRange }

    // MARK: - Derived display properties

    /// "Al-Fatiha - 1" style title for the current ayah, or empty string.
    var currentTrackTitle: String {
        guard let ayah = currentAyah else { return "" }
        if let end = currentAyahEnd, end != ayah {
            if end.surah == ayah.surah {
                return "\(metadata.surahName(ayah.surah)) - \(ayah.ayah)–\(end.ayah)"
            } else {
                return "\(metadata.surahName(ayah.surah)) \(ayah.ayah) – \(metadata.surahName(end.surah)) \(end.ayah)"
            }
        }
        return "\(metadata.surahName(ayah.surah)) - \(ayah.ayah)"
    }

    // MARK: - Init

    init(engine: PlaybackEngine, metadata: QuranMetadataService = .shared) {
        self.engine = engine
        self.metadata = metadata
    }

    // MARK: - Convenience play methods

    /// Builds a PlaybackSettingsSnapshot from a PlaybackSettings @Model and starts playback.
    /// `coveredAyahs` should be pre-computed on the main actor (e.g. from PlaybackSetupSheet)
    /// for all-local-reciter sessions so PlaybackQueue can skip gap ayahs between segments.
    func play(range: AyahRange,
              settings: PlaybackSettings,
              context: ModelContext,
              coveredAyahs: Set<AyahRef>? = nil) async {
        let snapshot = buildSnapshot(range: range, settings: settings, context: context,
                                     coveredAyahs: coveredAyahs)
        await engine.play(range: range, settings: snapshot)
    }

    /// Plays a recording's ayah range with no repeats and stop-after behavior.
    /// Does NOT modify the user's persisted PlaybackSettings.
    func playRecording(range: AyahRange, recording: Recording) async {
        guard let reciter = recording.reciter else { return }
        let snapshot = PlaybackSettingsSnapshot(
            range: range,
            connectionAyahBefore: 0,
            connectionAyahAfter: 0,
            speed: 1.0,
            ayahRepeatCount: 1,
            rangeRepeatCount: 1,
            afterRepeatAction: .stop,
            afterRepeatContinueAyaatCount: 0,
            afterRepeatContinuePagesCount: 0,
            afterRepeatContinuePagesExtraAyah: false,
            gapBetweenAyaatMs: 0,
            reciterPriority: [ReciterSnapshot(reciterId: reciter.id ?? UUID(), reciter: reciter)],
            segmentOverrides: [],
            riwayah: recording.safeRiwayah,
            coveredAyahs: coveredAyahsForRecording(recording)
        )
        await engine.play(range: range, settings: snapshot)
    }

    private func coveredAyahsForRecording(_ recording: Recording) -> Set<AyahRef>? {
        let segments = recording.segments ?? []
        guard !segments.isEmpty else { return nil }
        var covered = Set<AyahRef>()
        for seg in segments {
            guard let ss = seg.surahNumber, let sa = seg.ayahNumber else { continue }
            let es = seg.endSurahNumber ?? ss
            let ea = seg.endAyahNumber ?? sa
            var cur = AyahRef(surah: ss, ayah: sa)
            let end = AyahRef(surah: es, ayah: ea)
            while cur <= end {
                covered.insert(cur)
                guard let next = metadata.ayah(after: cur) else { break }
                cur = next
            }
        }
        return covered.isEmpty ? nil : covered
    }

    func pause()  { engine.pause() }
    func resume() { engine.resume() }
    func stop()   { engine.stop() }
    func setSpeed(_ speed: Double) { engine.setSpeed(speed) }
    func seek(to ayah: AyahRef) async { await engine.seek(to: ayah) }
    func skipToNextAyah() async { await engine.skipToNextAyah() }
    func skipToPreviousAyah() async { await engine.skipToPreviousAyah() }

    // MARK: - Repetition display

    var repetitionLabel: String? {
        guard totalAyahRepetitions != 1 || totalRangeRepetitions != 1 else { return nil }
        if totalAyahRepetitions == -1 {
            return "Rep ∞"
        }
        if totalAyahRepetitions > 1 {
            return "Rep \(currentAyahRepetition)/\(totalAyahRepetitions)"
        }
        return nil
    }

    // MARK: - Private

    private func buildSnapshot(range: AyahRange,
                                settings: PlaybackSettings,
                                context: ModelContext,
                                coveredAyahs: Set<AyahRef>? = nil) -> PlaybackSettingsSnapshot {
        let priorityEntries = settings.sortedReciterPriority
        var reciterSnapshots: [ReciterSnapshot] = []

        let allReciters = (try? context.fetch(FetchDescriptor<Reciter>())) ?? []
        if let pinnedId = settings.selectedReciterId,
           let reciter = allReciters.first(where: { $0.id == pinnedId }) {
            // Specific reciter selected — use only that one
            reciterSnapshots = [ReciterSnapshot(reciterId: pinnedId, reciter: reciter)]
        } else {
            // Auto — filter to reciters that have at least one source for the selected riwayah,
            // matching the view's matchingReciters(riwayah:) logic.
            let targetRiwayah = settings.safeRiwayah
            for entry in priorityEntries {
                guard let reciterId = entry.reciterId else { continue }
                guard let reciter = allReciters.first(where: { $0.id == reciterId }) else { continue }
                let hasCDNSource = (reciter.cdnSources ?? []).contains {
                    Riwayah(rawValue: $0.riwayah ?? "") == targetRiwayah
                }
                let hasSegment = (reciter.recordings ?? [])
                    .flatMap { $0.segments ?? [] }
                    .contains { $0.safeRiwayah == targetRiwayah }
                guard hasCDNSource || hasSegment else { continue }
                reciterSnapshots.append(ReciterSnapshot(reciterId: reciterId, reciter: reciter))
            }
        }

        let segmentOverrideSnapshots = (settings.segmentOverrides ?? [])
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
            .map { override -> SegmentOverrideSnapshot in
                let snapshots = override.sortedReciterPriority.compactMap { entry -> ReciterSnapshot? in
                    guard let rid = entry.reciterId,
                          let r = allReciters.first(where: { $0.id == rid }) else { return nil }
                    return ReciterSnapshot(reciterId: rid, reciter: r)
                }
                return SegmentOverrideSnapshot(range: override.ayahRange, reciterPriority: snapshots)
            }

        return PlaybackSettingsSnapshot(
            range: range,
            connectionAyahBefore: settings.connectionAyahBefore ?? 0,
            connectionAyahAfter: settings.connectionAyahAfter ?? 0,
            speed: settings.safeSpeed,
            ayahRepeatCount: settings.safeAyahRepeat,
            rangeRepeatCount: settings.safeRangeRepeat,
            afterRepeatAction: settings.safeAfterRepeatAction,
            afterRepeatContinueAyaatCount: settings.afterRepeatContinueAyaatCount ?? 0,
            afterRepeatContinuePagesCount: settings.afterRepeatContinuePagesCount ?? 0,
            afterRepeatContinuePagesExtraAyah: settings.afterRepeatContinuePagesExtraAyah ?? false,
            gapBetweenAyaatMs: settings.safeGapMs,
            reciterPriority: reciterSnapshots,
            segmentOverrides: segmentOverrideSnapshots,
            riwayah: settings.safeRiwayah,
            coveredAyahs: coveredAyahs
        )
    }
}
