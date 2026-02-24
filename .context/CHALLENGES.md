# Tilawa — Challenges & Solutions

**Version:** 1.0

This document catalogs known and predicted technical challenges, with proposed solutions for each.

---

## Challenge 1: Annotation Tedium (Known)

**Problem:** Tagging a 45-minute Friday prayer recording with correct ayah boundaries is extremely tedious if done manually frame-by-frame. A typical jumu'ah khutbah recitation could contain 50–100 ayaat, making manual annotation impractical.

**Solution: Three-Tier Annotation System**

**Tier 1 — Auto-detect:**
Run `SilenceDetector` immediately after import. For standard recitations with clear pauses between ayaat (>400ms), this achieves ~80–90% boundary accuracy. Suggestions are shown in amber/orange as "unconfirmed" markers, distinct from user-confirmed (blue) markers.

**Tier 2 — Guided Sequential Assignment:**
The annotation editor tracks the "last confirmed ayah" and pre-fills the next expected ayah for each segment (e.g., if last was Al-Baqarah 2:5, next suggestion is 2:6). The user hears each segment auto-play in a loop, then taps Confirm or adjusts. This turns 50 individual decisions into 50 quick confirmations.

**Tier 3 — Manual Precision:**
For continuous recitation (no gaps), the user can zoom the waveform to a 2-second window and place markers at sub-100ms precision. A slow-speed playback mode (0.5×) is available within the annotation editor for fine-grained placement.

**Additional UX shortcut:** If the user knows the surah and starting ayah, they can tap "Sequential fill from surah X, ayah Y" and the editor assigns sequential ayah numbers to all unconfirmed markers in order — one tap to annotate an entire surah.

---

## Challenge 2: Surah Boundary Recitations (Known)

**Problem:** Some reciters connect the end of one surah directly to the start of the next — especially Surah Al-Anfal (8:75) into At-Tawbah (9:1), which has no Basmallah between them. This creates a single audio segment that must serve two different ayah lookups. Similarly, some reciters use wasla at surah boundaries, making it impossible to find a clean cut point.

**Solution: Cross-Surah Segment Model**

`RecordingSegment` has:
- `isCrosssurahSegment: Bool?`
- `crossSurahJoinOffsetSeconds: Double?`
- `endSurahNumber: Int?` / `endAyahNumber: Int?`

**Annotation UX:**
1. User enables the "spans surah boundary" toggle in `SegmentAssignmentView`
2. A mini-waveform scrubber scoped to just that segment appears
3. User places the split point (even mid-word for wasla)
4. Two ayah refs are assigned: start-ayah (primary) and end-ayah

**Playback resolution:**
- When engine needs ayah 8:75 → use `startOffset` to `crossSurahJoinOffset`
- When engine needs ayah 9:1 → use `crossSurahJoinOffset` to `endOffset`
- RecordingLibraryService query covers both cases:
  ```swift
  (surahNumber == target.surah && ayahNumber == target.ayah) ||
  (endSurahNumber == target.surah && endAyahNumber == target.ayah && isCrosssurahSegment == true)
  ```

**Anfal/Tawbah special case:**
The Quran metadata bundle flags surah 9 as a "no-basmallah" surah. The playback engine skips the basmallah insertion step before surah 9 regardless of reciter. This prevents a floating basmallah from being inserted into the gap.

---

## Challenge 3: Missing Ayaat in Partial Recordings (Known)

**Problem:** The user wants to listen to Surah Al-Maidah (5:1–120) but their recording only covers ayaat 1–30. Or they have a recording of a taraweeh night that starts mid-surah. The playback engine encounters ayaat with no available source.

**Solution: Pre-Flight Coverage Check + Graceful Degradation**

**Pre-flight check (before playback starts):**
`PlaybackQueue` calls `RecordingLibraryService.missingAyaat(in:metadata:)` to get the list of ayaat with no audio from any enabled reciter. If any are missing, a non-blocking sheet appears:

```
"5 ayaat in this range have no audio:
  Al-Maidah 5:31, 5:32, 5:33, 5:34, 5:35

[ Fill from any available reciter ]   [ Continue anyway ]   [ Cancel ]
```

**"Fill from any reciter" option:** Temporarily overrides riwayah and reciter restrictions for only the missing ayaat, using whatever is available.

**Mid-playback handling (download fails, file becomes unavailable):**
1. `ReciterResolver` returns `nil`
2. Engine inserts a silence gap (minimum 500ms, configurable)
3. `playbackVM.unavailableAyah` is set → Mushaf highlights the ayah in amber for 2 seconds
4. Playback continues to the next ayah automatically
5. Missing ayah is logged to `ListeningSession` for user review

**Partial recording navigation:**
When the user opens `RecordingDetailView` for a partial recording, coverage gaps are visualized in the coverage summary: "Al-Fatiha 1:1–7 ✓ | Al-Baqarah 1:1–20 ✓ | 1:21–286 missing"

---

## Challenge 4: AVAudioEngine Interruptions and Background State (Predicted)

**Problem:** Phone calls, Siri, FaceTime, AirPlay switching, and Bluetooth headphone disconnection all interrupt `AVAudioSession`. iOS can also aggressively suspend or reclaim audio resources when the app is backgrounded for extended periods. `AVAudioEngine`'s node graph can become invalid after some interruption types.

**Solutions:**

**Interruption handling** (`AVAudioSession.interruptionNotification`):
- `.began` → `pause()` (saves exact position)
- `.ended` + `.shouldResume` → reactivate session + restart engine if not running + `resume()`

**Route change** (`AVAudioSession.routeChangeNotification`):
- `.oldDeviceUnavailable` (headphones unplugged) → `pause()` per Apple HIG — users expect audio to stop
- `.newDeviceAvailable` (Bluetooth connected) → no automatic action; user resumes manually

**Engine configuration change** (`AVAudioEngineConfigurationChange`):
- Rebuild the engine graph (re-attach + re-connect nodes)
- Re-schedule the current ayah from the last known sample position
- Restart the engine

**Background task safety:**
- `UIBackgroundModes: audio` keeps the engine alive
- For long sessions (4+ hours of taraweeh), periodically save `currentAyah` and `currentAyahRepetition` to `ListeningSession` so the user can resume if the app is terminated

---

## Challenge 5: iCloud Sync Order Mismatch (Predicted)

**Problem:** CloudKit syncs SwiftData metadata (Recording, RecordingSegment) immediately. But the actual audio file in iCloud Drive may not download to a new device for minutes or hours. The app shows annotated recordings that appear ready but crash or silently fail when the playback engine tries to open non-existent local files.

**Solution: File Availability Gating**

`RecordingLibraryService.availability(of:)` checks `ubiquitousItemDownloadingStatus` before any file is played or displayed as "ready."

UI States for recordings:
- `available` → normal playback enabled
- `cloudOnly` → iCloud icon badge; tap triggers `startDownloadingUbiquitousItem`
- `downloading(progress)` → progress ring
- `unavailable` → warning icon, playback disabled with explanation

`ReciterResolver` treats `cloudOnly` files identically to missing files — it skips them and tries the next priority reciter. This prevents playback failures on a fresh device install.

**NSMetadataQuery for download progress:**
Use `NSMetadataQuery` with `NSMetadataUbiquitousItemPercentDownloadedKey` for accurate progress tracking on the `cloudOnly → downloading → available` transition.

---

## Challenge 6: Word Highlighting at Non-1× Speed (Predicted)

**Problem:** Word timing JSON files encode timestamps from 1× playback. At 2× speed, the audio reaches the next word in half the time, but if we naively divide timing values by speed, the highlighting lags or races. Additionally, `AVAudioUnitTimePitch` alters the playback rate of the scheduled PCM buffers, so the relationship between engine sample time and file timestamp is not straightforward.

**Solution: playerNode.playerTime(forNodeTime:) maps correctly at all rates**

`AVAudioPlayerNode.playerTime(forNodeTime:)` returns the position within the **scheduled source file** (in its native sample rate), not in engine output time. Since the source file is always 1× speed, this value maps directly to the word timing JSON without any rate correction:

```swift
func currentWordIndex(item: AyahAudioItem, timings: [WordTiming]) -> Int? {
    guard let nodeTime = playerNode.lastRenderTime,
          let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return nil }
    // sampleTime is in the SOURCE file's sample clock (1× speed)
    let fileSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate
    let filePosition = item.startOffset + fileSeconds
    return timings.lastIndex { $0.startSeconds <= filePosition }
}
```

This is polled via `CADisplayLink` (60fps) in `MushafViewModel`. At 2× speed the highlighting advances twice as fast visually, which is correct behavior.

**Fallback for missing word timings:** Fall back to ayah-level highlighting (highlight the entire ayah number on the Mushaf page) when `item.wordTimings == nil`.

---

## Challenge 7: Ayah Count Standard Inconsistencies (Predicted)

**Problem:** Different Quran printing traditions disagree on ayah counts for several surahs. For example, some traditions count the Basmallah of Al-Fatiha as ayah 1 (making Al-Fatiha have 7 ayaat), while others do not (making it 6 + Basmallah). Off-by-one errors propagate into annotation, playback, and reciter file naming.

**Solution: Adopt One Authoritative Standard, Document It Explicitly**

Tilawa uses the **Hafs an Asim standard** (most common globally, used in the Medina mushaf):
- Total ayaat: **6,236**
- Al-Fatiha: 7 ayaat (Basmallah = ayah 1)
- Surah 9 (At-Tawbah): no Basmallah
- All reciter file naming uses this standard's surah/ayah numbering

This is hardcoded in `QuranMetadataService` and in all bundled metadata JSONs. The standard is documented at the top of `QuranMetadataService.swift` and in the README.

**Reciter file naming**: Files from external CDNs may use a different numbering (e.g., some CDNs skip the Basmallah as ayah 1 in Al-Fatiha). This is handled per-reciter in `Reciter.fileNamingPattern` with an optional `ayahOffset: Int?` field that adjusts the lookup.

---

## Challenge 8: SwiftData Optional Fields in Business Logic (Predicted)

**Problem:** Requiring all stored properties to be optional (for CloudKit compatibility) means every property access requires optional chaining or nil-coalescing. Code becomes verbose and brittle if optionals are unwrapped inconsistently. Sync conflicts (two devices writing simultaneously) can produce unexpected nil values.

**Solution: Layered API — Raw Model vs. Safe Computed Properties**

Each `@Model` class provides:
1. **Raw stored optionals** — only accessed in persistence layer (SwiftData queries, save operations)
2. **Safe computed properties** with explicit defaults — used in all business logic, UI bindings, and ViewModels

```swift
extension PlaybackSettings {
    var safeSpeed: Double { playbackSpeed ?? 1.0 }
    var safeAyahRepeat: Int { ayahRepeatCount ?? 1 }
    var safeRangeRepeat: Int { rangeRepeatCount ?? 1 }
    var safeRiwayah: Riwayah { Riwayah(rawValue: selectedRiwayah ?? "hafs") ?? .hafs }
    var safeAfterRepeatAction: AfterRepeatAction {
        AfterRepeatAction(rawValue: afterRepeatAction ?? "stop") ?? .stop
    }
}
```

**Sync conflict resolution:** SwiftData + CloudKit uses a last-write-wins strategy by default. For critical settings like reciter priority order, this is acceptable. For listening progress (`ListeningSession.lastAyah`), a CloudKit subscription can be used to detect conflicts and present a merge UI if needed.

**Schema migration:** Use `VersionedSchema` enums. New optional fields added in future versions default to `nil` on devices that haven't been updated yet — the safe computed properties handle this gracefully with their defaults.

---

## Challenge 9: Riwayah Switching Between Sessions (Updated)

**Principle:** Riwayah is strictly enforced at the session level. Mixing riwayahs within a single playback session is not permitted — it's a fiqh concern, not just a UX preference. A reciter in the priority list who doesn't match the session's `selectedRiwayah` is silently skipped by the resolver. If no reciter can serve an ayah in the correct riwayah, it produces a silence gap and an "unavailable" indicator — it does NOT fall back to a different riwayah.

**Switching riwayah:**
The user changes `PlaybackSettings.selectedRiwayah` in the settings screen. If playback is active, changing riwayah immediately stops the current session. The next play() call starts a fresh session with the new riwayah.

**Reciter list clarity:**
`ReciterPriorityView` groups reciters by riwayah. Reciters whose riwayah does not match the current `selectedRiwayah` are shown greyed out with a label: "Not available for [Hafs] — switch riwayah to use." This prevents confusion about why a reciter is never playing.

**Personal recordings and riwayah:**
When a user imports a recording, they tag its riwayah during the annotation setup (or it inherits from the associated `Reciter` entry). The resolver only uses personal recording segments whose riwayah tag matches the session riwayah. A recording of a Warsh reciter is never used during a Hafs session.

---

## Challenge 10: Large Waveform Files and Memory Pressure (Predicted)

**Problem:** A 90-minute taraweeh recording at 44.1kHz stereo produces ~480MB of raw PCM when read by `AVAssetReader`. Storing the full float array in memory is impractical. Even the downsampled amplitude array at 1000 points/second = 5.4M floats for a 90-minute recording.

**Solution: Fixed-Resolution Downsampling**

`WaveformAnalyzer` always downsample to a **fixed target of 1,000–2,000 sample points** regardless of recording duration. This is sufficient for visual waveform display at any screen width. The analyzer processes PCM in streaming chunks (never loading the full file into memory) and discards raw samples after computing each chunk's RMS.

For a 90-minute recording:
- Raw PCM processed in 4MB chunks → never more than 4MB in memory at once
- Output: 1,000 Float values = 4KB

**Waveform caching:** After the first analysis, the amplitude array is persisted to a small sidecar file in the app's Caches directory (`{recordingUUID}-waveform.bin`) so re-opening the annotation editor doesn't re-analyze.

---

## Challenge 11: Reciter Audio File Licensing and Distribution (Predicted)

**Problem:** Tilawa does not host reciter audio. Users must configure their own CDN base URL for each reciter. But many popular Quran CDNs (e.g., mp3quran.net, everyayah.com) have rate limits, CORS restrictions, or terms of service that restrict programmatic access.

**Solution: User-Configured Reciter Sources + Local-First Caching**

- Tilawa ships with a default list of well-known public reciter CDN patterns (documented with their known terms of service)
- Users add custom reciters by entering the base URL and file naming pattern themselves
- `AudioFileCache` downloads files on-demand and stores them permanently in the app's local cache
- Once cached, files play offline with no further CDN dependency
- Users are informed during reciter setup that they are responsible for complying with the source's terms of service

This is architecturally equivalent to how podcast apps work — they point to RSS feeds that users subscribe to, and cache locally.

---

## Summary Table

| # | Challenge | Severity | Solution Category |
|---|-----------|----------|-------------------|
| 1 | Annotation tedium | High | 3-tier UX + sequential fill |
| 2 | Surah boundary recordings | High | Cross-surah segment model |
| 3 | Missing ayaat | High | Pre-flight check + graceful degradation |
| 4 | AVAudioEngine interruptions | High | Comprehensive notification handling |
| 5 | iCloud sync order mismatch | Medium | File availability gating |
| 6 | Word highlight at non-1× | Medium | playerNode.playerTime() native mapping |
| 7 | Ayah count standards | Medium | Single authoritative standard (Hafs) |
| 8 | SwiftData optional verbosity | Medium | Layered API with safe computed properties |
| 9 | Riwayah switching between sessions | Low | Strict enforcement; session restart on change |
| 10 | Large waveform memory | Medium | Fixed-resolution streaming downsampling |
| 11 | Reciter file licensing | Low | User-configured + local-first caching |
