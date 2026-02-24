# Tilawa — Playback Engine Design

**Version:** 1.0

---

## 1. Overview

The playback engine is the core audio system. It is responsible for:
- Resolving which reciter/recording provides audio for each ayah
- Building and executing a gapless audio queue
- Enforcing repeat counts and after-repeat behavior
- Integrating with the iOS Now Playing UI and lock screen
- Handling background audio, interruptions, and route changes

The engine is an `@Observable` class (`PlaybackEngine`) consumed by `PlaybackViewModel`.

---

## 2. State Machine

```
States:
    idle              Initial; nothing queued
    loading           Fetching/decoding the next audio item
    playing           AVAudioPlayerNode actively playing
    paused            Paused mid-ayah; can resume
    awaitingRepeat    Ayah finished; inside the gap before next repetition
    awaitingNextAyah  Ayah repeat exhausted; gap before advancing to next ayah
    rangeComplete     All range repetitions done; awaiting after-repeat action
    error(Error)      Unrecoverable; displays error to user

Transitions:
    idle           --[play(range:settings:)]--> loading
    loading        --[itemReady]             --> playing
    loading        --[itemUnavailable]       --> loading (try next reciter) | error (all failed)
    playing        --[pause()]               --> paused
    paused         --[resume()]              --> playing
    playing        --[ayahComplete]          --> awaitingRepeat   (if ayahRepeat > 1 remaining)
                                             --> awaitingNextAyah (if ayahRepeat exhausted)
    awaitingRepeat --[gapElapsed]            --> loading (reload same ayah)
    awaitingNextAyah --[hasMoreAyaat]        --> loading (next ayah in range)
    awaitingNextAyah --[rangeEnd]            --> awaitingNextAyah (decrement rangeRepeat, restart range)
                                             --> rangeComplete (if rangeRepeat exhausted)
    rangeComplete  --[.stop]                 --> idle
    rangeComplete  --[.continueAyaat(N)]     --> loading (range.end + 1, for N ayaat)
    rangeComplete  --[.continuePages(N)]     --> loading (next N pages from range.end)
    any            --[stop()]               --> idle
    any            --[seek(to:)]            --> loading
```

---

## 3. PlaybackEngine Class

```swift
// Playback/PlaybackEngine.swift
import AVFoundation
import Observation

@Observable
final class PlaybackEngine {

    // MARK: - Public State (read by PlaybackViewModel)
    private(set) var state: PlaybackState = .idle
    private(set) var currentAyah: AyahRef?
    private(set) var currentAyahRepetition: Int = 0       // 1-based
    private(set) var totalAyahRepetitions: Int = 1         // -1 = infinite
    private(set) var currentRangeRepetition: Int = 0       // 1-based
    private(set) var totalRangeRepetitions: Int = 1        // -1 = infinite
    private(set) var currentReciterName: String = ""
    private(set) var currentRiwayah: Riwayah = .hafs
    private(set) var currentIsPersonalRecording: Bool = false
    private(set) var unavailableAyah: AyahRef? = nil       // set when resolver fails

    // MARK: - Private Engine Components
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitchUnit = AVAudioUnitTimePitch()

    private let resolver: ReciterResolver
    private let nowPlaying: NowPlayingCoordinator
    private let remoteCommands: RemoteCommandHandler

    // MARK: - Session State
    private var activeSnapshot: PlaybackSettingsSnapshot?
    private var activeRange: AyahRange?
    private var ayahQueue: [AyahRef] = []       // flat ordered list for current range
    private var currentQueueIndex: Int = 0

    // MARK: - Init
    init(resolver: ReciterResolver,
         nowPlaying: NowPlayingCoordinator,
         remoteCommands: RemoteCommandHandler) {
        self.resolver = resolver
        self.nowPlaying = nowPlaying
        self.remoteCommands = remoteCommands
        setupAudioEngine()
        registerInterruptionHandlers()
        remoteCommands.register(engine: self)
    }

    // MARK: - Public API
    func play(range: AyahRange, settings: PlaybackSettingsSnapshot) async
    func pause()
    func resume()
    func seek(to ayah: AyahRef) async
    func skipToNextAyah() async
    func skipToPreviousAyah() async
    func stop()
    func setSpeed(_ speed: Double)

    // MARK: - Internal
    private func setupAudioEngine()
    private func buildAyahQueue(from range: AyahRange,
                                settings: PlaybackSettingsSnapshot) -> [AyahRef]
    private func scheduleAyah(_ ref: AyahRef) async
    private func handleAyahCompletion() async
    private func advanceAyahRepetition() async
    private func advanceToNextAyah() async
    private func handleRangeCompletion() async
    private func registerInterruptionHandlers()
    private func handleInterruption(_ notification: Notification)
    private func handleRouteChange(_ notification: Notification)
}
```

---

## 4. AVAudioEngine Graph

```
[AVAudioPlayerNode]
        │
        ▼
[AVAudioUnitTimePitch]    ← controls playback rate (pitch-preserving)
        │
        ▼
[AVAudioEngine.mainMixerNode]
        │
        ▼
  [Audio Output]
```

```swift
// PlaybackEngine.setupAudioEngine()
private func setupAudioEngine() {
    // Configure session
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .default,
                             options: [.allowBluetooth, .allowAirPlay])
    try? session.setActive(true)

    // Build graph
    audioEngine.attach(playerNode)
    audioEngine.attach(timePitchUnit)
    audioEngine.connect(playerNode, to: timePitchUnit, format: nil)
    audioEngine.connect(timePitchUnit, to: audioEngine.mainMixerNode, format: nil)

    // Handle engine config changes (e.g., after interruption)
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleEngineConfigChange),
        name: .AVAudioEngineConfigurationChange,
        object: audioEngine
    )

    try? audioEngine.start()
}

// Speed control (pitch is preserved by AVAudioUnitTimePitch)
func setSpeed(_ speed: Double) {
    timePitchUnit.rate = Float(speed)
}
```

---

## 5. Segment Scheduling (UGC Sub-File Playback)

`AVAudioPlayerNode` supports scheduling a specific time range within a file, which is essential for UGC recordings where each segment has `startOffsetSeconds` and `endOffsetSeconds`.

```swift
private func scheduleSegment(_ item: AyahAudioItem,
                              completionHandler: @escaping () -> Void) throws {
    let audioFile = try AVAudioFile(forReading: item.audioURL)
    let sampleRate = audioFile.processingFormat.sampleRate
    let startFrame = AVAudioFramePosition(item.startOffset * sampleRate)
    let frameCount = AVAudioFrameCount((item.endOffset - item.startOffset) * sampleRate)

    playerNode.scheduleSegment(
        audioFile,
        startingFrame: startFrame,
        frameCount: frameCount,
        at: nil,
        completionCallbackType: .dataPlayedBack
    ) { _ in
        Task { @MainActor in
            completionHandler()
        }
    }
}
```

For standard reciter files (full file = one ayah), `startOffset = 0` and `endOffset = file duration`.

---

## 6. Gapless Playback

The engine pre-schedules the next ayah's audio segment before the current one finishes to eliminate audible gaps:

```
Timeline:
    |────────── Ayah N playing ──────────[80% complete: pre-schedule triggered]─|
                                                    │
                                                    ▼
                                        ReciterResolver.resolve(ayah N+1)
                                        AVAudioFile loaded
                                        playerNode.scheduleSegment(nextFile, at: nil)
                                                    │
    |── Ayah N finishes ──|──────────── Ayah N+1 plays immediately (gapless) ───────|
```

The 80% trigger uses a `CADisplayLink`-based polling of `playerNode.playerTime(forNodeTime:)` compared to the item's total frame count.

For the configurable gap (`gapBetweenAyaatMs > 0`), insert a silence buffer:

```swift
private func scheduleSilenceGap(durationMs: Int) {
    let format = audioEngine.mainMixerNode.inputFormat(forBus: 0)
    let frameCount = AVAudioFrameCount(Double(durationMs) / 1000.0 * format.sampleRate)
    guard let silenceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
    silenceBuffer.frameLength = frameCount
    // PCM buffer initialized to zero = silence
    playerNode.scheduleBuffer(silenceBuffer, at: nil, options: [], completionHandler: nil)
}
```

---

## 7. ReciterResolver

```swift
// Playback/ReciterResolver.swift
final class ReciterResolver {

    private let libraryService: RecordingLibraryService

    // Returns the best available AyahAudioItem for a given ayah ref.
    //
    // Resolution order per reciter entry (in priority list order):
    //   1. Personal recordings for this reciter (higher fidelity / sentimental value)
    //   2. CDN files for this reciter
    //
    // Riwayah is ALWAYS strictly enforced. Any reciter whose riwayah does not match
    // the session's selectedRiwayah is skipped entirely. No cross-riwayah fallback.
    func resolve(ref: AyahRef,
                 snapshot: PlaybackSettingsSnapshot) async -> AyahAudioItem? {

        for entry in snapshot.reciterPriority {
            let reciter = entry.reciter
            // Strict riwayah gate — skip the entire entry if riwayah doesn't match
            guard reciter.safeRiwayah == snapshot.riwayah else { continue }

            // Step 1: try personal recordings for this specific reciter
            if let item = await resolvePersonalRecording(ref: ref, reciter: reciter) {
                return item
            }

            // Step 2: try CDN files for this reciter
            if let item = await resolveCDN(ref: ref, reciter: reciter) {
                return item
            }
        }

        return nil  // triggers silence gap + unavailable indicator
    }

    // MARK: - Personal Recording Resolution (for a specific reciter)
    private func resolvePersonalRecording(ref: AyahRef,
                                          reciter: Reciter) async -> AyahAudioItem? {
        // Query segments linked to this specific reciter's recordings
        let allSegments = await libraryService.segments(for: ref, reciter: reciter)
        // Prefer: manually annotated first, then highest confidence, then most recent
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

        // Check file availability before returning
        guard isFileAvailable(url: url) else { return nil }

        return AyahAudioItem(
            id: UUID(),
            ayahRef: ref,
            audioURL: url,
            startOffset: best.startOffsetSeconds ?? 0,
            endOffset: best.endOffsetSeconds ?? recording.safeDuration,
            reciterName: recording.reciter?.safeName ?? "Personal Recording",
            reciterId: recording.reciter?.id ?? UUID(),
            isPersonalRecording: true,
            wordTimings: nil
        )
    }

    // MARK: - CDN Resolution
    private func resolveCDN(ref: AyahRef, reciter: Reciter) async -> AyahAudioItem? {
        let localURL = localFileURL(for: ref, reciter: reciter)
        if FileManager.default.fileExists(atPath: localURL.path) {
            let duration = await audioDuration(url: localURL) ?? 0
            let timings = await WordTimingProvider.shared.timings(for: ref, reciterId: reciter.id ?? UUID())
            return AyahAudioItem(
                id: UUID(),
                ayahRef: ref,
                audioURL: localURL,
                startOffset: 0,
                endOffset: duration,
                reciterName: reciter.safeName,
                reciterId: reciter.id ?? UUID(),
                isPersonalRecording: false,
                wordTimings: timings
            )
        }
        // File not cached; trigger background download and return nil
        Task { await AudioFileCache.shared.download(ref: ref, reciter: reciter) }
        return nil
    }

}
```

---

## 8. Ayah Queue Building

The queue accounts for connection ayaat and resolves the correct surah/ayah sequence across surah boundaries:

```swift
// PlaybackQueue.swift
func buildAyahQueue(range: AyahRange,
                    settings: PlaybackSettingsSnapshot,
                    metadata: QuranMetadataService) -> [AyahRef] {
    var queue: [AyahRef] = []

    // Connection ayah before
    if settings.connectionAyahBefore > 0 {
        if let prev = metadata.ayah(before: range.start) {
            queue.append(prev)
        }
    }

    // Main range
    var cursor = range.start
    while cursor <= range.end {
        queue.append(cursor)
        guard let next = metadata.ayah(after: cursor) else { break }
        cursor = next
    }

    // Connection ayah after
    if settings.connectionAyahAfter > 0 {
        if let next = metadata.ayah(after: range.end) {
            queue.append(next)
        }
    }

    return queue
}
```

---

## 9. Now Playing Integration

```swift
// Playback/NowPlayingCoordinator.swift
final class NowPlayingCoordinator {

    func update(item: AyahAudioItem,
                state: PlaybackState,
                ayahRep: Int, totalAyahRep: Int,
                rangeRep: Int, totalRangeRep: Int,
                elapsed: TimeInterval) {

        let surahName = QuranMetadataService.shared.surahName(item.ayahRef.surah)
        let ayahLabel = "Ayah \(item.ayahRef.surah):\(item.ayahRef.ayah)"
        let repLabel: String
        if totalRangeRep == -1 {
            repLabel = "Rep \(rangeRep) (∞)"
        } else {
            repLabel = "Rep \(rangeRep)/\(totalRangeRep)"
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: surahName,
            MPMediaItemPropertyArtist: item.reciterName,
            MPMediaItemPropertyAlbumTitle: "\(repLabel) · \(ayahLabel)",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPMediaItemPropertyPlaybackDuration: item.endOffset - item.startOffset,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
        ]

        // Artwork: use surah page image if available
        if let pageImage = MushafPageCache.shared.image(for: item.ayahRef) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: pageImage.size) { _ in pageImage }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
```

---

## 10. Remote Command Handler

```swift
// Playback/RemoteCommandHandler.swift
final class RemoteCommandHandler {

    weak var engine: PlaybackEngine?

    func register(engine: PlaybackEngine) {
        self.engine = engine
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.engine?.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.engine?.pause()
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            self?.engine?.stop()
            return .success
        }

        // Forward = next ayah
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { await self?.engine?.skipToNextAyah() }
            return .success
        }

        // Back = previous ayah
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { await self?.engine?.skipToPreviousAyah() }
            return .success
        }

        // Disable time-scrubbing from lock screen (ayah-level navigation only)
        center.changePlaybackPositionCommand.isEnabled = false
    }
}
```

---

## 11. Background Audio & Interruption Handling

```swift
// PlaybackEngine — interruption + route change handlers
private func registerInterruptionHandlers() {
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleInterruption(_:)),
        name: AVAudioSession.interruptionNotification,
        object: nil
    )
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleRouteChange(_:)),
        name: AVAudioSession.routeChangeNotification,
        object: nil
    )
}

@objc private func handleInterruption(_ notification: Notification) {
    guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

    switch type {
    case .began:
        pause()  // save position, stop node

    case .ended:
        let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        if options.contains(.shouldResume) {
            try? AVAudioSession.sharedInstance().setActive(true)
            // Re-start engine in case iOS reclaimed resources
            if !audioEngine.isRunning {
                try? audioEngine.start()
            }
            resume()
        }
    @unknown default:
        break
    }
}

@objc private func handleRouteChange(_ notification: Notification) {
    guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

    switch reason {
    case .oldDeviceUnavailable:
        // Headphones unplugged: pause per Apple HIG
        pause()
    case .newDeviceAvailable:
        // Bluetooth or AirPlay connected: no automatic action; user resumes manually
        break
    default:
        break
    }
}

@objc private func handleEngineConfigChange(_ notification: Notification) {
    // AVAudioEngine graph was reset (e.g., after aggressive background culling)
    // Rebuild and restart
    setupAudioEngine()
    if state == .playing || state == .paused {
        // Re-schedule the current ayah from the last known position
        Task { await scheduleAyah(currentAyah ?? ayahQueue[currentQueueIndex]) }
    }
}
```

---

## 12. Word-by-Word Highlight Sync

Word timing files are indexed at 1× speed. At non-1× speeds, the playback sample position still maps to the original file timeline because `AVAudioPlayerNode` schedules the raw file frames and `AVAudioUnitTimePitch` processes them — the file's sample clock is 1× regardless of rate.

```swift
// MushafViewModel.swift — CADisplayLink polling
private var displayLink: CADisplayLink?

func startWordHighlightPolling(item: AyahAudioItem) {
    stopWordHighlightPolling()
    displayLink = CADisplayLink(target: self, selector: #selector(updateWordHighlight))
    displayLink?.add(to: .main, forMode: .common)
    self.currentItem = item
}

@objc private func updateWordHighlight() {
    guard let item = currentItem,
          let timings = item.wordTimings,
          let nodeTime = playbackEngine.playerNode.lastRenderTime,
          let playerTime = playbackEngine.playerNode.playerTime(forNodeTime: nodeTime) else { return }

    // playerTime.sampleTime is the sample position in the source file
    let currentSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate

    // Adjust for segment start offset
    let filePosition = item.startOffset + currentSeconds

    let newIndex = timings.lastIndex { $0.startSeconds <= filePosition }
    if newIndex != highlightedWordIndex {
        highlightedWordIndex = newIndex
    }
}
```
