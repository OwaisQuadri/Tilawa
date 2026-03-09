import Observation
import Foundation

/// Orchestrates sliding-window memorization playback above the PlaybackEngine.
///
/// The coordinator calls `engine.play()` for each phase (solo, connection, full range)
/// and passively observes engine state to detect completion before advancing.
/// All skip/stop controls are handled by the engine natively.
@Observable @MainActor
final class SlidingWindowCoordinator {

    // MARK: - Public State

    private(set) var isActive = false
    private(set) var phase: Phase = .idle
    private(set) var currentAyahIndex = 0    // 0-based index within target ayahs
    private(set) var totalAyahCount = 0
    /// The after-repeat option from the base snapshot (the coordinator handles continuation internally).
    var afterRepeatOption: AfterRepeatOption { baseSnapshot.map { .from($0) } ?? .disabled }

    enum Phase: Equatable {
        case idle
        case solo
        case connection
        case fullRange
        case complete
    }

    /// 0.0–1.0 overall progress through the sliding window session.
    var overallProgress: Double {
        guard totalAyahCount > 0 else { return 0 }
        let ayahPhases = totalAyahCount  // each ayah has solo (+connection if not first)
        let totalPhases = ayahPhases + 1 // +1 for full range
        switch phase {
        case .idle, .complete:
            return phase == .complete ? 1.0 : 0.0
        case .solo, .connection:
            return Double(currentAyahIndex) / Double(totalPhases)
        case .fullRange:
            return Double(ayahPhases) / Double(totalPhases)
        }
    }

    /// Human-readable label for the current phase.
    var phaseLabel: String? {
        guard isActive else { return nil }
        switch phase {
        case .idle, .complete:
            return nil
        case .solo:
            return "Solo · Ayah \(currentAyahIndex + 1) of \(totalAyahCount)"
        case .connection:
            return "Connection · Ayah \(currentAyahIndex + 1) of \(totalAyahCount)"
        case .fullRange:
            return "Full Range"
        }
    }

    // MARK: - Dependencies

    private let engine: PlaybackEngine
    private let metadata: QuranMetadataService

    // MARK: - Session State

    private var targetAyahs: [AyahRef] = []
    private var swSettings = SlidingWindowSettings(perAyahRepeats: 5, connectionRepeats: 3,
                                                    connectionWindowSize: 2, fullRangeRepeats: 10)
    private var baseSnapshot: PlaybackSettingsSnapshot?
    private var sessionTask: Task<Void, Never>?
    /// Guards against race conditions: stale continuations exit when sessionID mismatches.
    private var sessionID = UUID()

    // MARK: - Init

    init(engine: PlaybackEngine, metadata: QuranMetadataService = .shared) {
        self.engine = engine
        self.metadata = metadata
    }

    // MARK: - Public API

    func start(range: AyahRange,
               baseSettings: PlaybackSettingsSnapshot,
               swSettings: SlidingWindowSettings) {
        stop()
        self.baseSnapshot = baseSettings
        self.swSettings = swSettings
        self.targetAyahs = buildAyahList(range: range)
        self.totalAyahCount = targetAyahs.count
        self.currentAyahIndex = 0
        self.isActive = true
        self.phase = .idle
        self.sessionID = UUID()

        sessionTask = Task { [weak self] in
            await self?.runSession()
        }
    }

    func stop() {
        let wasActive = isActive
        isActive = false
        sessionID = UUID()  // Invalidate any in-flight continuations
        sessionTask?.cancel()
        sessionTask = nil
        phase = .idle
        currentAyahIndex = 0
        totalAyahCount = 0
        targetAyahs = []
        baseSnapshot = nil
        // Stop the engine if the coordinator was driving it, so no stale
        // phase keeps playing after the coordinator exits. Use deactivateSession: false
        // since the caller (ViewModel.stop or ViewModel.play) handles session lifecycle.
        if wasActive {
            engine.stop(deactivateSession: false)
        }
    }

    // MARK: - Session Runner

    private func runSession() async {
        guard baseSnapshot != nil else { return }
        let capturedSession = sessionID

        // Phase 1 & 2: For each ayah, solo then connection
        for i in 0..<targetAyahs.count {
            guard isActive, sessionID == capturedSession else { return }
            currentAyahIndex = i
            let ayah = targetAyahs[i]

            // Solo phase
            phase = .solo
            let soloRange = AyahRange(start: ayah, end: ayah)
            if let base = baseSnapshot {
                let soloSnapshot = phaseSnapshot(base: base, range: soloRange,
                                                  ayahRepeat: swSettings.perAyahRepeats, rangeRepeat: 1)
                await engine.play(range: soloRange, settings: soloSnapshot)
            }
            guard isActive, sessionID == capturedSession else { return }
            await waitForPhaseEnd()
            guard isActive, sessionID == capturedSession else { return }

            // Connection phase (skip only if ayah has no predecessor, i.e. 1:1)
            let ayahHasPredecessor = metadata.ayah(before: ayah) != nil
            if ayahHasPredecessor {
                phase = .connection
                let connectionStart = walkBack(from: ayah, steps: swSettings.connectionWindowSize)
                let connectionRange = AyahRange(start: connectionStart, end: ayah)
                if let base = baseSnapshot {
                    let connectionSnapshot = phaseSnapshot(base: base, range: connectionRange,
                                                            ayahRepeat: 1, rangeRepeat: swSettings.connectionRepeats)
                    await engine.play(range: connectionRange, settings: connectionSnapshot)
                }
                guard isActive, sessionID == capturedSession else { return }
                await waitForPhaseEnd()
                guard isActive, sessionID == capturedSession else { return }
            }
        }

        // Phase 3: Full range
        guard isActive, sessionID == capturedSession, let base = baseSnapshot else { return }
        phase = .fullRange
        let fullSnapshot = phaseSnapshot(base: base, range: base.range,
                                          ayahRepeat: 1, rangeRepeat: swSettings.fullRangeRepeats)
        await engine.play(range: base.range, settings: fullSnapshot)
        guard isActive, sessionID == capturedSession else { return }
        await waitForPhaseEnd()
        guard isActive, sessionID == capturedSession else { return }

        // After full range: apply "after repeating" action
        if let newRange = await computeContinuationRange(base: base) {
            guard isActive, sessionID == capturedSession else { return }
            targetAyahs = buildAyahList(range: newRange)
            totalAyahCount = targetAyahs.count
            currentAyahIndex = 0
            baseSnapshot = continuationSnapshot(base: base, newRange: newRange)
            // Recurse into a new session for the continuation range
            await runSession()
        } else {
            phase = .complete
            isActive = false
        }
    }

    // MARK: - Helpers

    private func waitForPhaseEnd() async {
        while isActive {
            let state = engine.state
            if state == .idle { return }
            if case .error = state { return }
            // Wait for next state change using observation tracking
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = engine.state
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }

    /// Builds a flat ayah list for the target range.
    private func buildAyahList(range: AyahRange) -> [AyahRef] {
        var list: [AyahRef] = []
        var cursor = range.start
        while cursor <= range.end {
            list.append(cursor)
            guard let next = metadata.ayah(after: cursor) else { break }
            cursor = next
        }
        return list
    }

    /// Walks backwards from `ref` by `steps` ayahs, clamping at 1:1.
    private func walkBack(from ref: AyahRef, steps: Int) -> AyahRef {
        var cursor = ref
        for _ in 0..<steps {
            guard let prev = metadata.ayah(before: cursor) else { break }
            cursor = prev
        }
        return cursor
    }

    /// Computes the next range based on the "after repeating" action, or nil to stop.
    private func computeContinuationRange(base: PlaybackSettingsSnapshot) async -> AyahRange? {
        switch base.afterRepeatAction {
        case .stop:
            return nil

        case .continueAyaat:
            let count = base.afterRepeatContinueAyaatCount
            guard count > 0, let lastRef = targetAyahs.last,
                  let nextRef = metadata.ayah(after: lastRef) else { return nil }
            let continuation = PlaybackQueue.buildContinuation(from: nextRef, count: count, metadata: metadata)
            guard let first = continuation.first, let last = continuation.last else { return nil }
            return AyahRange(start: first, end: last)

        case .continuePages:
            let count = base.afterRepeatContinuePagesCount
            guard count > 0, let lastRef = targetAyahs.last else { return nil }
            let continuation = await PlaybackQueue.buildPageContinuation(
                after: lastRef, pageCount: count,
                extraAyah: base.afterRepeatContinuePagesExtraAyah,
                metadata: metadata
            )
            guard let first = continuation.first, let last = continuation.last else { return nil }
            return AyahRange(start: first, end: last)
        }
    }

    /// Creates a new base snapshot with an updated range for continuation.
    private func continuationSnapshot(base: PlaybackSettingsSnapshot, newRange: AyahRange) -> PlaybackSettingsSnapshot {
        PlaybackSettingsSnapshot(
            range: newRange,
            connectionAyahBefore: base.connectionAyahBefore,
            connectionAyahAfter: base.connectionAyahAfter,
            speed: base.speed,
            ayahRepeatCount: base.ayahRepeatCount,
            rangeRepeatCount: base.rangeRepeatCount,
            afterRepeatAction: base.afterRepeatAction,
            rangeRepeatBehavior: base.rangeRepeatBehavior,
            afterRepeatContinueAyaatCount: base.afterRepeatContinueAyaatCount,
            afterRepeatContinuePagesCount: base.afterRepeatContinuePagesCount,
            afterRepeatContinuePagesExtraAyah: base.afterRepeatContinuePagesExtraAyah,
            gapBetweenAyaatMs: base.gapBetweenAyaatMs,
            reciterPriority: base.reciterPriority,
            segmentOverrides: base.segmentOverrides,
            riwayah: base.riwayah,
            coveredAyahs: base.coveredAyahs
        )
    }

    /// Creates a per-phase snapshot by overriding range and repeat counts from the base snapshot.
    private func phaseSnapshot(base: PlaybackSettingsSnapshot,
                                range: AyahRange,
                                ayahRepeat: Int,
                                rangeRepeat: Int) -> PlaybackSettingsSnapshot {
        PlaybackSettingsSnapshot(
            range: range,
            connectionAyahBefore: 0,
            connectionAyahAfter: 0,
            speed: base.speed,
            ayahRepeatCount: ayahRepeat,
            rangeRepeatCount: rangeRepeat,
            afterRepeatAction: .stop,
            rangeRepeatBehavior: .whileRepeatingAyahs,
            afterRepeatContinueAyaatCount: 0,
            afterRepeatContinuePagesCount: 0,
            afterRepeatContinuePagesExtraAyah: false,
            gapBetweenAyaatMs: base.gapBetweenAyaatMs,
            reciterPriority: base.reciterPriority,
            segmentOverrides: base.segmentOverrides,
            riwayah: base.riwayah,
            coveredAyahs: base.coveredAyahs
        )
    }
}
