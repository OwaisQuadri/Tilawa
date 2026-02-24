# Tilawa — Technical Architecture

**Version:** 1.0
**iOS Target:** 17.0+
**Swift:** 5.9+

---

## 1. Technology Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| UI | SwiftUI | Declarative, iOS 17 features |
| State management | `@Observable` macro | Replaces `ObservableObject`; no `@Published` needed |
| Persistence | SwiftData + CloudKit | All `@Model` fields optional for CloudKit compat |
| Audio playback | `AVAudioEngine` + `AVAudioPlayerNode` | Pitch-independent speed, sub-file time ranges |
| Speed control | `AVAudioUnitTimePitch` | Preserves pitch at non-1× rates |
| Now Playing | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` | Lock screen, CarPlay |
| Audio session | `AVAudioSession` (.playback) | Background audio |
| Waveform | `AVAssetReader` + `vDSP` (Accelerate) | RMS amplitude analysis for waveform display |
| Silence detection | `vDSP_rmsqv` on PCM buffers | Auto-boundary suggestions |
| iCloud files | `FileManager` ubiquity container | Audio file storage; CloudKit handles metadata |
| Networking | `URLSession` async/await | Reciter audio downloads |
| Background tasks | `UIBackgroundModes: audio` in Info.plist | Engine keeps running in background |

---

## 2. Folder Structure

```
Tilawa/
├── TilawaApp.swift                         // @main, ModelContainer, environment injection
├── Info.plist                              // UIBackgroundModes: [audio, remote-notification]
├── Tilawa.entitlements                     // CloudKit, Push (container ID must be populated)
│
├── Core/
│   ├── Models/                             // SwiftData @Model classes
│   │   ├── PlaybackSettings.swift
│   │   ├── ReciterPriorityEntry.swift
│   │   ├── Reciter.swift
│   │   ├── Recording.swift
│   │   ├── RecordingSegment.swift
│   │   ├── AyahMarker.swift
│   │   ├── UserBookmark.swift
│   │   └── ListeningSession.swift
│   │
│   ├── QuranData/                          // Bundled static Quran metadata
│   │   ├── QuranMetadataService.swift      // Surah names, ayah counts, page mappings
│   │   ├── QuranIndex.swift                // Value types: AyahRef, PageRef, AyahRange
│   │   └── WordTimingProvider.swift        // Load per-ayah word timing JSON files
│   │
│   └── Extensions/
│       ├── AVAsset+Duration.swift
│       └── CMTime+Seconds.swift
│
├── Playback/
│   ├── PlaybackEngine.swift                // @Observable — central audio coordinator
│   ├── PlaybackQueue.swift                 // Builds ordered [AyahAudioItem] from settings
│   ├── PlaybackStateMachine.swift          // enum PlaybackState with all transitions
│   ├── AyahAudioItem.swift                 // Value type: URL + timeRange + reciterInfo
│   ├── ReciterResolver.swift               // Priority-based reciter selection algorithm
│   ├── AudioFileCache.swift                // Local cache of downloaded reciter files
│   ├── NowPlayingCoordinator.swift         // MPNowPlayingInfoCenter updates
│   └── RemoteCommandHandler.swift          // MPRemoteCommandCenter registration
│
├── UGC/
│   ├── RecordingImporter.swift             // Files/VoiceMemos import + ubiquity copy
│   ├── WaveformAnalyzer.swift              // AVAssetReader → [Float] amplitude array
│   ├── SilenceDetector.swift               // vDSP RMS → [SilenceRegion] boundaries
│   ├── AnnotationEngine.swift              // Marker placement, segment creation
│   └── RecordingLibraryService.swift       // SwiftData CRUD for recordings/segments
│
├── ViewModels/
│   ├── AppViewModel.swift                  // @Observable — navigation, global state
│   ├── MushafViewModel.swift               // @Observable — page, highlight, word index
│   ├── PlaybackViewModel.swift             // @Observable — wraps PlaybackEngine for UI
│   ├── SettingsViewModel.swift             // @Observable — reads/writes PlaybackSettings
│   ├── RecordingLibraryViewModel.swift     // @Observable — recording list, filters
│   └── AnnotationViewModel.swift           // @Observable — waveform + marker editing
│
├── Views/
│   ├── Root/
│   │   ├── RootView.swift                  // TabView entry; receives all environments
│   │   └── AppTabBar.swift
│   │
│   ├── Mushaf/
│   │   ├── MushafView.swift                // Main reading view
│   │   ├── MushafPageView.swift            // Single page image + highlight overlay
│   │   ├── AyahHighlightOverlay.swift      // Canvas-based word/ayah highlight
│   │   └── RepetitionBadge.swift           // "Rep 3/5" persistent badge
│   │
│   ├── NowPlaying/
│   │   ├── MiniPlayerBar.swift             // Persistent bottom bar over all tabs
│   │   ├── FullPlayerSheet.swift           // Full player as a sheet/modal
│   │   ├── PlaybackControlsView.swift      // Play/pause/skip/speed controls
│   │   └── ReciterInfoView.swift           // Current reciter name + riwayah chip
│   │
│   ├── Settings/
│   │   ├── PlaybackSettingsView.swift      // All playback settings in one screen
│   │   ├── ReciterPriorityView.swift       // Drag-to-reorder list
│   │   ├── LoopSettingsView.swift          // Ayah + range repeat pickers
│   │   └── AfterRepeatSettingsView.swift   // Continue behavior after range repeat
│   │
│   ├── UGC/
│   │   ├── RecordingLibraryView.swift      // List of all recordings with coverage
│   │   ├── RecordingDetailView.swift       // Metadata + segment list per recording
│   │   ├── AnnotationEditorView.swift      // Full waveform annotation workspace
│   │   ├── WaveformView.swift              // Canvas waveform renderer + marker overlays
│   │   ├── AyahMarkerView.swift            // Draggable marker handle component
│   │   └── SegmentAssignmentView.swift     // Assign surah:ayah to a waveform segment
│   │
│   └── Shared/
│       ├── SurahPickerView.swift
│       ├── AyahPickerView.swift
│       └── LoadingIndicatorView.swift
│
└── Resources/
    ├── QuranData/
    │   ├── quran-metadata.json             // Surah names, ayah counts, juz, page mapping
    │   ├── page-ayah-mapping.json          // page N → [AyahRef] list
    │   └── word-timings/                   // {reciterId}/{surah}-{ayah}.json timing files
    └── Fonts/
        └── UthmanTahaNaskh.ttf             // optional; only if text-based rendering used
```

---

## 3. ViewModel Responsibilities

All ViewModels use `@Observable` (Swift 5.9+), NOT `ObservableObject`.

### `AppViewModel`
- Selected tab index
- Navigation paths per tab (using `NavigationPath`)
- Global loading / error state
- iCloud sync status
- Onboarding completion flags
- Coordinates showing onboarding flow on first launch

### `MushafViewModel`
- `currentPage: Int` — drives page display
- `highlightedAyah: AyahRef?` — drives ayah highlight
- `highlightedWordIndex: Int?` — drives word highlight
- `tappableAyahRegions: [AyahRef: CGRect]` — populated by page layout engine
- `scrollOffset: CGFloat` — for programmatic scrolling
- Handles page-turn animation direction
- Observes `PlaybackViewModel.currentAyah` to update page and highlight

### `PlaybackViewModel`
- Thin adapter over `PlaybackEngine`
- Exposes for UI: `isPlaying`, `currentAyah`, `currentAyahRepetition`, `totalAyahRepetitions`, `currentRangeRepetition`, `totalRangeRepetitions`, `currentReciterName`, `currentRiwayah`, `isPersonalRecording`, `speed`, `state`
- Forwards user actions: `play(range:settings:)`, `pause()`, `resume()`, `seek(to:)`, `skipToNextAyah()`, `skipToPreviousAyah()`, `stop()`, `setSpeed(_:)`
- Observes engine state to update NowPlaying via `NowPlayingCoordinator`

### `SettingsViewModel`
- Holds reference to `PlaybackSettings` SwiftData model (fetched via `@Query` in the view or injected)
- Provides computed bindings for all UI controls
- Validates: start must precede end, speed within bounds, repeat counts within range
- `snapshotForPlayback() -> PlaybackSettingsSnapshot` — called by PlaybackViewModel before play()

### `RecordingLibraryViewModel`
- Queries `Recording` models filtered by annotation status, surah coverage
- Manages delete confirmation flow
- Triggers import flow (calls `RecordingImporter`)
- Provides sorting: by date, duration, coverage completeness
- `coverageSummary(for: Recording) -> String` — e.g., "Al-Fatiha 1–7, Al-Baqarah 1–5"

### `AnnotationViewModel`
- `amplitudes: [Float]` — loaded async from `WaveformAnalyzer`
- `markers: [AyahMarker]` — current set of placed markers (ordered by time)
- `selectedMarkerIndex: Int?` — which marker is being edited
- `isPlayingSegment: Bool`, `segmentPlaybackPosition: Double`
- `autoDetect()` — calls `SilenceDetector`, creates unconfirmed markers
- `addMarker(at time: Double)` — insert new marker
- `moveMarker(id: UUID, to time: Double)` — drag handler
- `assignAyah(markerId: UUID, surah: Int, ayah: Int)` — confirm a marker
- `saveAnnotations()` — converts markers into `RecordingSegment` models via `AnnotationEngine`

---

## 4. Environment Injection Pattern

```swift
// TilawaApp.swift
@main
struct TilawaApp: App {
    @State private var appVM = AppViewModel()
    @State private var playbackVM = PlaybackViewModel()
    @State private var mushafVM = MushafViewModel()
    @State private var settingsVM = SettingsViewModel()
    @State private var libraryVM = RecordingLibraryViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appVM)
                .environment(playbackVM)
                .environment(mushafVM)
                .environment(settingsVM)
                .environment(libraryVM)
        }
        .modelContainer(sharedModelContainer)
    }
}

// Consuming view example
struct MushafView: View {
    @Environment(PlaybackViewModel.self) private var playbackVM
    @Environment(MushafViewModel.self) private var mushafVM
    // ...
}

// AnnotationViewModel is NOT in global environment — it's scoped to the annotation flow:
struct AnnotationEditorView: View {
    @State private var annotationVM = AnnotationViewModel(recording: recording)
    var body: some View {
        AnnotationWorkspace()
            .environment(annotationVM)
    }
}
```

**Rule:** ViewModels that are globally relevant (playback, mushaf state) are injected at the root. ViewModels scoped to a specific screen (annotation, recording detail) are created locally with `@State` and injected only into that subtree.

---

## 5. Data Flow

```
User taps ayah on Mushaf
        │
        ▼
MushafView.onAyahTapped(ref: AyahRef)
        │
        ├──▶ mushafVM.selectAyah(ref)
        │         └──▶ updates highlightedAyah → MushafPageView re-renders
        │
        └──▶ playbackVM.seek(to: ref)
                  │
                  ▼
            PlaybackEngine.seek(to: ref)
                  │
                  ▼
            PlaybackQueue.buildItem(for: ref, settings: snapshot)
                  │
                  ▼
            ReciterResolver.resolve(ref: ref, priority: snapshot.reciterPriority)
                  │
                  ├──▶ Check personal recordings (SwiftData query)
                  └──▶ Check each named reciter in priority order
                            │
                            ▼
                      AyahAudioItem (URL, startOffset, endOffset, reciterName)
                            │
                            ▼
                  AVAudioPlayerNode.scheduleSegment(...)
                            │
                            ▼
                  NowPlayingCoordinator.update(item:state:repetition:)
                            │
                            ▼
                  playbackVM.$currentAyah publishes
                            │
                            ▼
                  mushafVM observes → updates page + highlight
```

---

## 6. Key Architectural Decisions

### Decision 1: AVAudioEngine over AVQueuePlayer
`AVQueuePlayer` cannot play a time range within a file. UGC segments require `startOffset` and `endOffset` within a longer recording. `AVAudioEngine` + `AVAudioPlayerNode.scheduleSegment(_:startingFrame:frameCount:at:)` supports exact frame-level precision. Additionally, `AVAudioUnitTimePitch` provides pitch-preserving speed control that `AVPlayer.rate` does not.

### Decision 2: Pre-rendered page images for Mushaf
Use 604 PNG/WebP page images bundled or downloaded on first launch, rendered in a `ScrollView` / `TabView`. A transparent `Canvas` overlay layer handles highlighting. This gives pixel-perfect Al Madinah fidelity without complex Arabic text layout engine work. Word boundary rectangles per page are stored in a bundled JSON lookup table indexed by `AyahRef` + word index.

### Decision 3: iCloud Drive for audio files, CloudKit for metadata
Large audio files (UGC recordings, cached reciter files) use `FileManager` ubiquity container. SwiftData models store the relative path within the container. CloudKit (via SwiftData's automatic integration) handles metadata sync. This separates large binary sync (iCloud Drive) from structured data sync (CloudKit), avoiding CloudKit record size limits.

### Decision 4: Immutable settings snapshot at play-time
`PlaybackSettingsSnapshot` (a value type, not `@Model`) is captured when the user taps play. Changes to `PlaybackSettings` during playback do NOT affect the current session. This prevents race conditions and confusing mid-session behavior changes.

### Decision 5: All `@Model` properties optional
Required for CloudKit sync via SwiftData. Each model exposes non-optional computed convenience properties (e.g., `safeSpeed`, `safeRiwayah`) with safe defaults for UI consumption and business logic. Direct access to stored optionals is limited to persistence layer code.

---

## 7. Info.plist Required Keys

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>               <!-- ADD: required for background playback -->
    <string>remote-notification</string> <!-- already present -->
</array>
<key>NSMicrophoneUsageDescription</key>
<string>Tilawa uses the microphone to record Quran recitations.</string>
<key>NSAppleMusicUsageDescription</key>
<string>Tilawa can import recordings from your Voice Memos library.</string>
```

---

## 8. Entitlements Required

```xml
<!-- Tilawa.entitlements -->
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.yourteam.Tilawa</string>  <!-- MUST populate before CloudKit works -->
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
    <string>CloudDocuments</string>               <!-- for ubiquity container / iCloud Drive -->
</array>
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array>
    <string>iCloud.com.yourteam.Tilawa</string>
</array>
```
