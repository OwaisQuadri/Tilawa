import AVFoundation
import Observation

@Observable
final class PlaybackEngine {

    // MARK: - Public State

    private(set) var state: PlaybackState = .idle
    private(set) var currentAyah: AyahRef?
    private(set) var currentAyahEnd: AyahRef?   // end of the currently playing ayah range
    private(set) var currentAyahRepetition: Int = 0       // 1-based
    private(set) var totalAyahRepetitions: Int = 1        // -1 = infinite
    private(set) var currentRangeRepetition: Int = 0      // 1-based
    private(set) var totalRangeRepetitions: Int = 1       // -1 = infinite
    private(set) var currentReciterName: String = ""
    private(set) var currentIsPersonalRecording: Bool = false
    private(set) var unavailableAyah: AyahRef?
    private(set) var currentSpeed: Double = 1.0

    // MARK: - AVAudio Graph

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitchUnit = AVAudioUnitTimePitch()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 3)

    // MARK: - Dependencies

    private let resolver: ReciterResolver
    private let nowPlaying: NowPlayingCoordinator
    private let remoteCommands: RemoteCommandHandler
    private let metadata: QuranMetadataService

    // MARK: - Session State

    private var activeSnapshot: PlaybackSettingsSnapshot?
    private var ayahQueue: [AyahRef] = []
    private var currentQueueIndex: Int = 0
    private var currentItem: AyahAudioItem?
    private var sessionID: UUID = UUID()   // Invalidated on stop/play to guard stale callbacks
    private var ayahStartDate: Date?       // Wall-clock time when current ayah began playing
    private var pausedElapsedTime: TimeInterval = 0  // Elapsed when last paused
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var engineConfigObserver: NSObjectProtocol?

    // MARK: - Init

    init(resolver: ReciterResolver = ReciterResolver(),
         nowPlaying: NowPlayingCoordinator = NowPlayingCoordinator(),
         remoteCommands: RemoteCommandHandler = RemoteCommandHandler(),
         metadata: QuranMetadataService = .shared) {
        self.resolver = resolver
        self.nowPlaying = nowPlaying
        self.remoteCommands = remoteCommands
        self.metadata = metadata
        setupAudioEngine()
        registerInterruptionHandlers()
        remoteCommands.register(engine: self)
    }

    deinit {
        if let obs = interruptionObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = routeChangeObserver  { NotificationCenter.default.removeObserver(obs) }
        if let obs = engineConfigObserver { NotificationCenter.default.removeObserver(obs) }
        remoteCommands.unregister()
        nowPlaying.clear()
    }

    // MARK: - Public API

    /// Start playback for a range with a settings snapshot.
    func play(range: AyahRange, settings: PlaybackSettingsSnapshot) async {
        stop()
        // Re-activate audio session to ensure Now Playing eligibility
        try? AVAudioSession.sharedInstance().setActive(true)
        if !audioEngine.isRunning { try? audioEngine.start() }
        // Apply speed from settings before scheduling audio
        currentSpeed = settings.speed
        timePitchUnit.rate = Float(settings.speed)
        activeSnapshot = settings
        totalAyahRepetitions = settings.ayahRepeatCount
        totalRangeRepetitions = settings.rangeRepeatCount
        currentRangeRepetition = 1
        ayahQueue = PlaybackQueue.build(range: range, settings: settings, metadata: metadata)
        currentQueueIndex = 0
        print("▶️ PlaybackEngine.play: queue=\(ayahQueue.count) ayaat, reciters=\(settings.reciterPriority.count), riwayah=\(settings.riwayah.rawValue), engineRunning=\(audioEngine.isRunning)")
        await scheduleCurrentAyah()
    }

    func pause() {
        guard state == .playing else { return }
        playerNode.pause()
        pausedElapsedTime = currentElapsedInAyah()
        ayahStartDate = nil
        state = .paused
        updateNowPlaying()
    }

    func resume() {
        guard state == .paused else { return }
        playerNode.play()
        ayahStartDate = Date()
        state = .playing
        updateNowPlaying()
    }

    func stop() {
        sessionID = UUID()   // Invalidate any in-flight completion callbacks
        ayahStartDate = nil
        pausedElapsedTime = 0
        playerNode.stop()
        state = .idle
        currentAyah = nil
        currentAyahEnd = nil
        currentItem = nil
        activeSnapshot = nil
        ayahQueue = []
        currentQueueIndex = 0
        currentAyahRepetition = 0
        currentRangeRepetition = 0
        unavailableAyah = nil
        nowPlaying.clear()
    }

    func seek(to ayah: AyahRef) async {
        guard let snapshot = activeSnapshot else { return }
        // Find the ayah in the queue, or rebuild from this point
        if let idx = ayahQueue.firstIndex(of: ayah) {
            currentQueueIndex = idx
        } else {
            ayahQueue = PlaybackQueue.build(
                range: AyahRange(start: ayah, end: snapshot.range.end),
                settings: snapshot,
                metadata: metadata
            )
            currentQueueIndex = 0
        }
        currentAyahRepetition = 0
        playerNode.stop()
        await scheduleCurrentAyah()
    }

    @MainActor
    func skipToNextAyah() async {
        guard !ayahQueue.isEmpty, activeSnapshot != nil else { return }
        sessionID = UUID()   // Invalidate any in-flight completion callback
        playerNode.stop()
        let nextIndex = currentQueueIndex + 1
        if nextIndex < ayahQueue.count {
            // Next ayah exists in this pass — jump immediately (no inter-ayah gap)
            currentQueueIndex = nextIndex
            await scheduleCurrentAyah()
        } else {
            // End of queue — honour range-repeat / afterRepeat / stop (same as natural completion)
            await handleRangeCompletion()
        }
    }

    @MainActor
    func skipToPreviousAyah() async {
        guard !ayahQueue.isEmpty else { return }
        sessionID = UUID()   // Invalidate any in-flight completion callback
        playerNode.stop()
        // On first ayah: restart it. Otherwise: go to start of the previous ayah.
        if currentQueueIndex > 0 { currentQueueIndex -= 1 }
        await scheduleCurrentAyah()
    }

    func setSpeed(_ speed: Double) {
        currentSpeed = speed
        timePitchUnit.rate = Float(speed)
        updateNowPlaying()
    }

    // MARK: - AVAudioEngine Setup

    private func setupAudioEngine() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default,
                                  options: [.allowBluetoothA2DP, .allowAirPlay])
        try? session.setActive(true)

        if audioEngine.isRunning { audioEngine.stop() }

        // EQ: voice isolation (high-pass rumble cut, presence boost, hiss shelf cut)
        let bands = eqNode.bands
        bands[0].filterType = .highPass;   bands[0].frequency = 100;  bands[0].bypass = false
        bands[1].filterType = .parametric; bands[1].frequency = 3000; bands[1].bandwidth = 1.0
        bands[1].gain = 2.5; bands[1].bypass = false
        bands[2].filterType = .highShelf;  bands[2].frequency = 8000; bands[2].gain = -2.5
        bands[2].bypass = false

        audioEngine.attach(playerNode)
        audioEngine.attach(timePitchUnit)
        audioEngine.attach(eqNode)
        audioEngine.connect(playerNode, to: timePitchUnit, format: nil)
        audioEngine.connect(timePitchUnit, to: eqNode, format: nil)
        audioEngine.connect(eqNode, to: audioEngine.mainMixerNode, format: nil)

        do {
            try audioEngine.start()
        } catch {
            state = .error(.engineStartFailed(error))
        }
    }

    // MARK: - Scheduling

    private func scheduleCurrentAyah() async {
        // Capture session at entry so we can detect stop()/play() races after each await
        let capturedSession = sessionID

        guard currentQueueIndex < ayahQueue.count,
              let snapshot = activeSnapshot else {
            state = .idle
            return
        }

        let ref = ayahQueue[currentQueueIndex]
        await MainActor.run {
            state = .loading
            currentAyah = ref  // Must be on MainActor so @Observable triggers SwiftUI from any call site
        }
        print("🔍 scheduleCurrentAyah: \(ref.surah):\(ref.ayah) [\(currentQueueIndex)/\(ayahQueue.count-1)]")

        guard let item = await resolver.resolve(ref: ref, snapshot: snapshot) else {
            // Guard against stale session after the async resolve
            guard sessionID == capturedSession else { return }
            print("❌ No audio for \(ref.surah):\(ref.ayah)")
            await MainActor.run { unavailableAyah = ref }
            // Insert silence gap and advance
            scheduleSilenceGap(durationMs: max(snapshot.gapBetweenAyaatMs, 500))
            await advanceToNextAyah()
            return
        }

        // Guard again — stop() may have been called while resolver was awaiting
        guard sessionID == capturedSession else { return }

        await MainActor.run {
            unavailableAyah = nil
            currentItem = item
            currentAyahEnd = item.endAyahRef
            currentReciterName = item.reciterName
            currentIsPersonalRecording = item.isPersonalRecording
            currentAyahRepetition = (currentAyahRepetition == 0) ? 1 : currentAyahRepetition
        }

        do {
            try scheduleSegment(item) { [weak self, capturedSession] in
                Task {
                    // Only handle completion if we're still in the same playback session
                    guard self?.sessionID == capturedSession else { return }
                    await self?.handleAyahCompletion()
                }
            }
            if !playerNode.isPlaying {
                playerNode.play()
            }
            ayahStartDate = Date()
            pausedElapsedTime = 0
            state = .playing
            updateNowPlaying()  // elapsed=0, rate=1.0 → system auto-advances the slider
        } catch {
            // File is likely corrupted — delete it so it gets re-downloaded next time
            print("⚠️ scheduleSegment failed for \(ref.surah):\(ref.ayah): \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: item.audioURL)
            await MainActor.run { unavailableAyah = ref }
            scheduleSilenceGap(durationMs: max(snapshot.gapBetweenAyaatMs, 500))
            await advanceToNextAyah()
        }
    }

    private func scheduleSegment(_ item: AyahAudioItem,
                                  completionHandler: @escaping () -> Void) throws {
        let audioFile = try AVAudioFile(forReading: item.audioURL)
        let sampleRate = audioFile.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(item.startOffset * sampleRate)
        let totalFrames = AVAudioFramePosition(audioFile.length)
        let endFrame = item.endOffset > item.startOffset
            ? AVAudioFramePosition(item.endOffset * sampleRate)
            : totalFrames
        let frameCount = AVAudioFrameCount(max(0, endFrame - startFrame))

        guard frameCount > 0 else {
            completionHandler()
            return
        }

        let isPersonal = item.isPersonalRecording
        eqNode.auAudioUnit.shouldBypassEffect = !isPersonal
        playerNode.volume = normalizedVolume(for: audioFile, startFrame: startFrame, frameCount: frameCount, isPersonal: isPersonal)

        playerNode.scheduleSegment(
            audioFile,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            Task { @MainActor in completionHandler() }
        }
    }

    /// Computes a volume gain to bring the segment's RMS level close to -18 dBFS.
    /// Personal recordings: samples 3 windows (10 / 50 / 90 %) for a representative estimate.
    /// CDN: quick single-window at the start.
    private func normalizedVolume(for audioFile: AVAudioFile,
                                   startFrame: AVAudioFramePosition,
                                   frameCount: AVAudioFrameCount,
                                   isPersonal: Bool) -> Float {
        let format = audioFile.processingFormat
        let sampleRate = Float(format.sampleRate)
        let channels = Int(format.channelCount)
        var sumSquares: Float = 0
        var totalSamples: Int = 0

        func accumulate(from windowStart: AVAudioFramePosition, windowFrames: AVAudioFrameCount) {
            let available = AVAudioFrameCount(max(0, Int64(frameCount) - (windowStart - startFrame)))
            let count = min(windowFrames, available)
            guard count > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return }
            audioFile.framePosition = windowStart
            guard (try? audioFile.read(into: buffer, frameCount: count)) != nil,
                  buffer.frameLength > 0,
                  let channelData = buffer.floatChannelData else { return }
            let length = Int(buffer.frameLength)
            for ch in 0..<channels {
                let samples = channelData[ch]
                for i in 0..<length { sumSquares += samples[i] * samples[i] }
            }
            totalSamples += length * channels
        }

        let windowFrames = AVAudioFrameCount(sampleRate * 0.5)   // 0.5 s per window

        if isPersonal {
            // 3 windows at 10 %, 50 %, 90 % of the segment
            for ratio: Float in [0.1, 0.5, 0.9] {
                let offset = AVAudioFramePosition(Float(frameCount) * ratio)
                accumulate(from: startFrame + offset, windowFrames: windowFrames)
            }
        } else {
            // CDN: one window at the start
            accumulate(from: startFrame, windowFrames: min(AVAudioFrameCount(sampleRate), frameCount))
        }

        guard totalSamples > 0 else { return 1.0 }
        let rms = sqrtf(sumSquares / Float(totalSamples))
        guard rms > 0.0001 else { return 1.0 }   // near-silence; don't adjust

        // Target ~-18 dBFS (≈ 0.126 RMS). Clamp to ±12 dB.
        let gain = 0.126 / rms
        return min(max(gain, 0.25), 4.0)
    }

    private func scheduleSilenceGap(durationMs: Int) {
        guard durationMs > 0 else { return }
        let format = audioEngine.mainMixerNode.inputFormat(forBus: 0)
        let frameCount = AVAudioFrameCount(Double(durationMs) / 1000.0 * format.sampleRate)
        guard let silenceBuffer = AVAudioPCMBuffer(pcmFormat: format,
                                                    frameCapacity: frameCount) else { return }
        silenceBuffer.frameLength = frameCount
        playerNode.scheduleBuffer(silenceBuffer, at: nil, options: [], completionHandler: nil)
    }

    // MARK: - Completion Handling

    @MainActor
    private func handleAyahCompletion() async {
        guard let snapshot = activeSnapshot else { return }

        let isInfiniteAyahRepeat = totalAyahRepetitions == -1
        let moreAyahReps = isInfiniteAyahRepeat || currentAyahRepetition < totalAyahRepetitions

        if moreAyahReps {
            // Schedule gap then repeat
            state = .awaitingRepeat
            if snapshot.gapBetweenAyaatMs > 0 {
                scheduleSilenceGap(durationMs: snapshot.gapBetweenAyaatMs)
                try? await Task.sleep(nanoseconds: UInt64(snapshot.gapBetweenAyaatMs) * 1_000_000)
            }
            currentAyahRepetition += 1
            await scheduleCurrentAyah()
        } else {
            await advanceToNextAyah()
        }
    }

    @MainActor
    private func advanceToNextAyah() async {
        guard let snapshot = activeSnapshot else { return }
        state = .awaitingNextAyah
        currentAyahRepetition = 1

        // Skip any queue entries already covered by the just-played item's ayah range
        var nextIndex = currentQueueIndex + 1
        if let item = currentItem, item.coversRange {
            while nextIndex < ayahQueue.count && ayahQueue[nextIndex] <= item.endAyahRef {
                nextIndex += 1
            }
        }

        if nextIndex < ayahQueue.count {
            // More ayaat in the current range pass
            currentQueueIndex = nextIndex
            if snapshot.gapBetweenAyaatMs > 0 {
                scheduleSilenceGap(durationMs: snapshot.gapBetweenAyaatMs)
                try? await Task.sleep(nanoseconds: UInt64(snapshot.gapBetweenAyaatMs) * 1_000_000)
            }
            await scheduleCurrentAyah()
        } else {
            // End of queue — check range repeat
            await handleRangeCompletion()
        }
    }

    @MainActor
    private func handleRangeCompletion() async {
        guard let snapshot = activeSnapshot else { return }

        let isInfiniteRangeRepeat = totalRangeRepetitions == -1
        let moreRangeReps = isInfiniteRangeRepeat || currentRangeRepetition < totalRangeRepetitions

        if moreRangeReps {
            currentRangeRepetition += 1
            currentQueueIndex = 0
            currentAyahRepetition = 1
            await scheduleCurrentAyah()
        } else {
            state = .rangeComplete
            nowPlaying.clear()

            switch snapshot.afterRepeatAction {
            case .stop:
                stop()

            case .continueAyaat:
                let count = snapshot.afterRepeatContinueAyaatCount
                guard count > 0, let lastRef = ayahQueue.last,
                      let nextRef = metadata.ayah(after: lastRef) else {
                    stop()
                    return
                }
                let continuation = PlaybackQueue.buildContinuation(
                    from: nextRef, count: count, metadata: metadata
                )
                guard !continuation.isEmpty else { stop(); return }
                ayahQueue = continuation
                currentQueueIndex = 0
                currentAyahRepetition = 1
                currentRangeRepetition = 1
                await scheduleCurrentAyah()

            case .continuePages:
                let count = snapshot.afterRepeatContinuePagesCount
                guard count > 0, let lastRef = ayahQueue.last else { stop(); return }
                let continuation = PlaybackQueue.buildPageContinuation(
                    after: lastRef, pageCount: count, metadata: metadata
                )
                guard !continuation.isEmpty else { stop(); return }
                ayahQueue = continuation
                currentQueueIndex = 0
                currentAyahRepetition = 1
                currentRangeRepetition = 1
                await scheduleCurrentAyah()
            }
        }
    }

    // MARK: - Now Playing

    private func updateNowPlaying() {
        guard let item = currentItem else { return }
        nowPlaying.update(
            item: item,
            state: state,
            speed: currentSpeed,
            ayahRep: currentAyahRepetition,
            totalAyahRep: totalAyahRepetitions,
            rangeRep: currentRangeRepetition,
            totalRangeRep: totalRangeRepetitions,
            elapsed: elapsedSeconds()
        )
    }

    /// Elapsed time within the current ayah (wall-clock, resets to 0 at each new ayah).
    private func currentElapsedInAyah() -> TimeInterval {
        let sinceStart = ayahStartDate.map { Date().timeIntervalSince($0) } ?? 0
        return pausedElapsedTime + sinceStart
    }

    private func elapsedSeconds() -> TimeInterval {
        guard let item = currentItem else { return 0 }
        return item.startOffset + currentElapsedInAyah()
    }

    // MARK: - Interruption & Route Change Handlers

    private func registerInterruptionHandlers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }

        engineConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            self?.handleEngineConfigChange()
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            pause()
        case .ended:
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                try? AVAudioSession.sharedInstance().setActive(true)
                if !audioEngine.isRunning {
                    try? audioEngine.start()
                }
                resume()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged — pause per Apple HIG
            pause()
        case .newDeviceAvailable:
            // A new audio output (e.g. AirPods) connected — restart engine so it routes to it
            setupAudioEngine()
        default:
            break
        }
    }

    private func handleEngineConfigChange() {
        setupAudioEngine()
        if state == .playing || state == .paused {
            Task {
                let ref = currentAyah ?? (ayahQueue.indices.contains(currentQueueIndex)
                    ? ayahQueue[currentQueueIndex]
                    : nil)
                if let ref {
                    await seek(to: ref)
                }
            }
        }
    }
}
