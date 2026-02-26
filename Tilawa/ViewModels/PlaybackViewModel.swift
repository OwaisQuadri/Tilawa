import Observation
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
    var currentReciterName: String { engine.currentReciterName }
    var currentAyahRepetition: Int { engine.currentAyahRepetition }
    var totalAyahRepetitions: Int { engine.totalAyahRepetitions }
    var currentRangeRepetition: Int { engine.currentRangeRepetition }
    var totalRangeRepetitions: Int { engine.totalRangeRepetitions }
    var isPlaying: Bool { engine.state == .playing }
    var unavailableAyah: AyahRef? { engine.unavailableAyah }

    // MARK: - Derived display properties

    /// "Al-Fatiha - 1" style title for the current ayah, or empty string.
    var currentTrackTitle: String {
        guard let ayah = currentAyah else { return "" }
        return "\(metadata.surahName(ayah.surah)) - \(ayah.ayah)"
    }

    // MARK: - Init

    init(engine: PlaybackEngine, metadata: QuranMetadataService = .shared) {
        self.engine = engine
        self.metadata = metadata
    }

    // MARK: - Convenience play method

    /// Builds a PlaybackSettingsSnapshot from a PlaybackSettings @Model and starts playback.
    func play(range: AyahRange,
              settings: PlaybackSettings,
              context: ModelContext) async {
        let snapshot = buildSnapshot(range: range, settings: settings, context: context)
        await engine.play(range: range, settings: snapshot)
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
                                context: ModelContext) -> PlaybackSettingsSnapshot {
        let priorityEntries = settings.sortedReciterPriority
        var reciterSnapshots: [ReciterSnapshot] = []

        let allReciters = (try? context.fetch(FetchDescriptor<Reciter>())) ?? []
        if let pinnedId = settings.selectedReciterId,
           let reciter = allReciters.first(where: { $0.id == pinnedId }) {
            // Specific reciter selected — use only that one
            reciterSnapshots = [ReciterSnapshot(reciterId: pinnedId, reciter: reciter)]
        } else {
            // Auto — use full priority list
            for entry in priorityEntries {
                guard let reciterId = entry.reciterId else { continue }
                if let reciter = allReciters.first(where: { $0.id == reciterId }) {
                    reciterSnapshots.append(ReciterSnapshot(reciterId: reciterId, reciter: reciter))
                }
            }
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
            gapBetweenAyaatMs: settings.safeGapMs,
            reciterPriority: reciterSnapshots,
            riwayah: settings.safeRiwayah
        )
    }
}
