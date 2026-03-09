# Backlogged Tasks

Deferred work, sorted by ROI (value ÷ effort). Items near the top deliver the
most impact for the least work.

---

## 1. Jump-to Recents Should Persist Between Sessions

**Problem**
The Recents tab in the jump-to sheet loses its history when the app is
relaunched. Users who frequently navigate to the same ayahs have to re-find
them each session.

**What's needed**
- Ensure `JumpHistory` entries (already SwiftData `@Model`) persist across app
  launches — they may already be persisted but not queried correctly on relaunch
- Verify that `ListeningSession` history (merged into recents) also persists
- If recents are built from in-memory state, switch to a `@Query` or
  `FetchDescriptor` so they survive restarts

**Scope**: Tiny — likely a query/persistence fix, no new models needed.

---

## 2. Move CDN Download Status to Manage CDN Screen

**Problem**
The reciter list row currently shows CDN download status inline, cluttering the
row with progress indicators and state that only matters when actively managing
downloads.

**What's needed**
- Remove CDN download status indicators from the reciter row view
- Add a top section in the Manage CDN screen showing overall download status
  (progress, count of downloaded/total surahs, active downloads)
- Keep the per-surah download state visible within the Manage CDN screen itself

**Scope**: Small — move existing UI components from one view to another.

---

## 3. Multiple Segments From the Same Recording for the Same Ayah

**Problem**
A salah recording may contain Fatiha recited multiple times (once per rak'ah).
The annotation editor currently doesn't have a smooth workflow for marking
multiple segments that map to the same ayah within a single recording. The data
model already supports competing segments with priority ordering
(`userSortOrder`), but the annotation UX doesn't guide users through this.

**What's needed**
- Allow placing multiple markers for the same (surah, ayah) in a single
  annotation session without warnings or overwriting
- When saving, create separate `RecordingSegment`s for each occurrence and
  assign sequential `userSortOrder` values
- Consider a visual indicator in the waveform showing "this ayah already has a
  segment earlier in this recording"

**Scope**: Medium — annotation editor state-machine changes + minor UI work.

---

## 4. Re-enable Warsh/Qaloon in Riwayah Compat Builder

**Problem**
`Scripts/riwayah_compat_builder.py` currently skips Warsh and Qaloon because
comparing (surah, ayah) positions across riwayat directly gives wrong pairings
(Hafs 1:2 Al-Hamd was paired with the wrong Warsh ayah). Task 1 unblocks this.

**What's needed**
- Re-enable `warsh` and `qaloon` in `SOURCES` in the builder script
- Before comparing Hafs and Warsh/Qaloon text at each position, translate the
  Hafs `AyahRef` to the native Warsh/Qaloon number using the offset map JSON
  (the builder is a Python script, so read the JSON directly rather than calling
  the Swift service)
- Re-run the builder to regenerate `riwayah_compatibility.json`

**Scope**: self-contained script change + regenerating one JSON file.

---

## 5. Fuzzy Search Ayah Text in Jump-to Menu

**Problem**
The jump sheet supports numeric queries (`10:5`, `p 100`, `juz 2`) and fuzzy
surah-name matching, but you can't search by ayah text itself. Users who
remember a phrase but not its location have no way to jump there directly.

**What's needed**
- Add an Arabic text search mode to `JumpToAyahSheet`
- Search against the Hafs text corpus (already available via
  `RiwayahTextService` or bundled JSON)
- Use fuzzy/substring matching tolerant of tashkeel (diacritics) — match on
  stripped consonantal skeleton, display full text in results
- Show a scrollable results list with (surah:ayah, snippet) rows; tapping a
  result jumps to that page

**Scope**: Medium — needs Arabic text normalization, search logic, and a results
list UI. No new data files required.

---

## 6. Finalize Should Strip Audio Between Ayah Segments

**Problem**
When finalizing a recording, the app preserves all audio between segments. If a
recording has `1:1–1:7` from `0:00` to `0:30` and then `1:7` closes without a new
ayah starting, with no marker until `19:1` at `0:45`, the gap from `0:30` to `0:45`
is dead air. Finalize should strip/crop out such gaps so the exported audio contains
only the marked ayah segments with no silence or unrecited audio between them.

**What's needed**
- During finalize, identify gaps between consecutive segments (where the end of one
  segment is not immediately followed by the start of the next)
- Use `AVAssetExportSession` to export only the marked time ranges, concatenating
  them without the gaps
- Preserve original audio quality and format

**Scope**: Moderate — requires changes to the finalize/export pipeline to compose
multiple time ranges into a single output file.

---

## 7. Sliding Window Range/Repeat Mode

**Problem**
Memorization workflows follow a structured pattern: repeat a single ayah N
times, then connect it with preceding ayahs, then advance — but the current
repeat modes don't automate this. Users must manually adjust ranges and repeat
counts as they progress through a page.

**What's needed**

### Playback behaviour
Given a target memorization range (e.g. one page), the sliding-window mode
works as follows:
1. Play ayah *i* alone, repeat it **A** times (default 5)
2. Play a connection range: ayah *i* plus the **C** ayahs before it
   (default 2 preceding ayahs), repeat this range **B** times (default 3)
3. Advance *i* by 1 and repeat steps 1–2 until the end of the target range
4. Play the entire target range, repeat it **D** times (default 10)

### Settings & persistence
- Parameters **A** (per-ayah repeats), **B** (connection repeats),
  **C** (connection window size), and **D** (full-range repeats) are
  user-configurable and persist via `@AppStorage`
- Add presets for common repeat-count combinations (similar to existing range
  presets) — e.g. "Light review" (3/2/1/5), "Deep memorization" (10/5/3/15)
- Presets are user-editable and persistable

### UI
- New mode option in the range/repeat picker (alongside existing modes)
- Compact summary showing current step (e.g. "Ayah 3 of 7 — connection pass")
- Progress indicator for the overall memorization session

**Scope**: Large — new playback state machine, settings UI, preset management,
and integration with `PlaybackEngine`/`PlaybackQueue`.

---

## 8. Displaying Masahif for Non-Hafs Riwayahs

**Problem**
The app currently renders the Hafs mushaf text for all sessions. If a user
selects Warsh, they hear the Warsh recitation but read the Hafs text — which
may differ at variant positions.

**What's needed**
- `RiwayahTextService` (added in PR #30) provides correct per-riwayah text —
  it just needs to be wired to the mushaf view
- The mushaf renderer uses QPC glyph fonts (Hafs-only); non-Hafs riwayat need
  a Unicode/Amiri-font fallback rendering path
- Navigation/highlighting must use `AyahOffsetService` to translate between
  Hafs internal positions and native Warsh/Qaloon ayah numbers

**Dependency**
Task 4 is done. Requires a decision on the Unicode rendering approach before
Swift model changes.

---

## 9. Compatibility Rethink for Different-Ayah-Count Riwayahs

**Problem**
The current compatibility model assumes all riwayahs share the same ayah
numbering (Hafs 6236). When a riwayah has a different count, the concept of
"compatible at ayah X" breaks down — ayah X in Hafs may not exist in Warsh,
or may correspond to a different ayah number.

**What's needed**
A richer compatibility model that can express:
- "Hafs 1:1 (Bismillah) has no equivalent in Warsh" → always incompatible
- "Hafs 1:2 (Al-Hamd) is textually equivalent to Warsh 1:1 (Al-Hamd)"

This may require storing cross-riwayah ayah mappings alongside the compatibility
groups, and updating `RiwayahCompatibilityService.swift` and `ReciterResolver.swift`
to use them.

**Dependency**
Requires tasks 4 and 8 to be completed first, since they all share the same
underlying alignment model.

---

## 10. Auto-Segment Recordings via Quran Detection

**Problem**
All annotation is currently manual — users place markers on a waveform to
identify ayah boundaries. For long recordings this is tedious. Automatic
detection of which ayahs are being recited (and where they start/end) would
dramatically reduce annotation effort.

**What's needed**
- Investigate existing open-source Quran recognition models:
  - [offline-tarteel](https://github.com/yazinsai/offline-tarteel) — offline
    Quran verse detection
  - Other tarteel.ai open-source work
- Evaluate Apple's on-device speech recognition (`SFSpeechRecognizer`) for
  Arabic — transcribe audio, then compare phonetic output against known ayah
  text using edit-distance or phonetic similarity
- Build a pipeline: audio → transcription/embedding → ayah matching → segment
  markers with confidence scores
- If no off-the-shelf model is accurate enough, consider fine-tuning a model on
  labeled Tilawa recordings (the app already produces labeled data via manual
  annotation)

**Scope**: Very large — ML model integration or training, Arabic speech
processing, accuracy tuning. Potentially the highest-impact feature long-term
but requires significant R&D.

---

## 11. Reciter CDN Import Rework + Admin Review System

**Problem**
Currently, importing a CDN source requires manually entering a URL or manifest.
There is no way to discover available reciters, and no moderation system for
user-uploaded CDN sources.

**What's needed**

### Discovery & Import
- A searchable list of reciter presets when importing a CDN source
- Fuzzy search by reciter name and riwayah
- Preset list is the union of: (a) hardcoded presets bundled in the app, and
  (b) a dynamic list hosted on the CDN (e.g. `manifests/index.json`)
- Selecting a preset auto-fills the CDN source config (base URL, format,
  naming pattern, riwayah)

### Admin Review System
- An admin mode (hidden or gated) for reviewing user-uploaded CDN sources
- A review queue listing CDN sources pending approval
- Each item in the queue can be: put in review, rejected, or accepted
- Accepted CDN sources are added to the public-facing preset list on the CDN
- Rejected sources are flagged and not listed

**Scope**: Large — requires Worker API changes (listing endpoint, review
endpoints), app UI for preset search, admin UI for the review queue, and a
decision on how admin auth works (separate API key, device-based, etc.).
