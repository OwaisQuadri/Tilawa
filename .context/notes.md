# Notes & In-Progress Context

## Playback Engine Testing Checklist

- [x] Step 1 — Seeding: `print("✅ Seeded reciter: ...")` in `TilawaApp.seedDefaultReciterIfNeeded()`
- [x] Step 2 — Test UI: Temporary "⚠️ Playback Test" section (**removed from SettingsView**)
- [x] Step 3 — Real cached file test: MP3s resolve correctly, state transitions to "playing ▶"
  - EveryAyah folder name is `Minshawy_Murattal_128kbps` (with **y**), not `Minshawi_`
  - `minshawi_murattal.json` base_url corrected accordingly
- [x] Step 4 — Now Playing fix implemented:
  - Re-activates audio session in `play()` for Now Playing eligibility
  - Adds `MPNowPlayingInfoPropertyMediaType` + `MPNowPlayingInfoPropertyIsLiveStream`
  - **Verify on device**: lock screen shows "Al-Fatiha - 1" / "Muhammad Siddiq Al-Minshawi"
  - next/prev track buttons advance ayah

- [ ] Step 5 — Manifest import:
  - Create a JSON file matching ReciterManifest schema with e.g. `"riwayah": "warsh"`
  - AirDrop to device → open with Tilawa
  - Confirm reciter appears with correct riwayah (needs import UI — deferred)

## Completed (This Session)
- [x] MiniPlayerBar — springs in above tab bar when audio is active
- [x] FullPlayerSheet — half/full sheet, play/pause/prev/next/stop, ayah info
- [x] MushafView ayah highlight — follows PlaybackEngine.currentAyah, auto-navigates page
- [x] SettingsView — removed test section; added Reciters list + Speed/Gap/Repeat pickers
- [x] PlaybackViewModel — added `currentTrackTitle`; all debug prints removed
- [x] PlaybackEngine, ReciterResolver — all debug prints removed

## Playback Reliability Fixes (done)
- [x] Race condition: `sessionID: UUID` guard added to `PlaybackEngine` — stale completion
  callbacks from previous `stop()`/`play()` cycles are silently discarded
- [x] Corrupted file handling: `scheduleSegment` catch block now deletes the bad file
  (`FileManager.removeItem`) and advances past it with a silence gap instead of entering
  terminal `.error` state — bad files are re-downloaded on the next play attempt

## Remaining Cleanup
- Seeding `print("✅ Seeded reciter: ...")` in TilawaApp can be removed once seeding is confirmed stable
- Debug prints in PlaybackEngine / ReciterResolver / PlaybackSetupSheet can be removed before shipping
