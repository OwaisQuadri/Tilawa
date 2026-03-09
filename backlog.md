# Backlogged Tasks

Deferred work, sorted by ROI (value ÷ effort). Items near the top deliver the
most impact for the least work.

**New ticket ID: TIL-21**

| # | Task | Scope |
|---|------|-------|
| TIL-2 | [Show Total Playback Time in Setup Sheet](#til-2-show-total-playback-time-in-setup-sheet) | Small |
| TIL-3 | [Bismillah Before Each Surah (Except Tawbah)](#til-3-bismillah-before-each-surah-except-tawbah) | Small |
| TIL-4 | [Add Haptic Feedback](#til-4-add-haptic-feedback) | Small |
| TIL-5 | [Re-enable Warsh/Qaloon in Riwayah Compat Builder](#til-5-re-enable-warshqaloon-in-riwayah-compat-builder) | Small |
| TIL-6 | [Fuzzy Search Ayah Text in Jump-to Menu](#til-6-fuzzy-search-ayah-text-in-jump-to-menu) | Medium |
| TIL-8 | [Displaying Masahif for Non-Hafs Riwayahs](#til-8-displaying-masahif-for-non-hafs-riwayahs) | Large |
| TIL-9 | [Horizontal Two-Page Landscape Layout](#til-9-horizontal-two-page-landscape-layout) | Large |
| TIL-10 | [Compatibility Rethink for Different-Ayah-Count Riwayahs](#til-10-compatibility-rethink-for-different-ayah-count-riwayahs) | Large |
| TIL-11 | [Auto-Segment Recordings via Quran Detection](#til-11-auto-segment-recordings-via-quran-detection) | Very Large |
| TIL-12 | [Reciter CDN Import Rework + Admin Review System](#til-12-reciter-cdn-import-rework--admin-review-system) | Large |

### Parallel work groups

Tasks grouped by file-overlap so each group can run on its own branch with
minimal merge conflicts. Work any **one task per group** at a time; groups
themselves are safe to run in parallel.

| Group | Tasks | Key files touched |
|-------|-------|-------------------|
| A — Jump-to sheet | TIL-6 | `JumpToAyahSheet`, `JumpHistory` |
| B — Playback engine | TIL-2, TIL-3 | `PlaybackSetupSheet`, `PlaybackQueue`, `PlaybackEngine`, `PlaybackSettings` |
| C — CDN / Library UI | TIL-12 | `RecitersView`, `ReciterDetailView`, CDN views |
| E — Riwayah data | TIL-5, TIL-10 | `Scripts/`, `RiwayahCompatibilityService`, `ReciterResolver` |
| F — Mushaf rendering | TIL-8, TIL-9 | `MushafView`, `MushafPageView`, `MushafViewModel` |
| G — Haptics (do last) | TIL-4 | Touches many views — best merged after other UI work |
| H — ML / R&D | TIL-11 | Mostly new files, independent |

---

## TIL-2. Show Total Playback Time in Setup Sheet

**Problem**
When configuring a playback session, there is no indication of how long it will
take. Users picking a full juz with 10× repeats have no idea if that's a
20-minute or 3-hour commitment until they press play.

**What's needed**
- Compute an estimated total playback time based on the selected range, repeat
  settings, speed, and gap between ayaat
- Display the estimate in the `PlaybackSetupSheet` Form (e.g. below the repeat
  section or near the Play button): "Estimated time: ~1h 23m"
- For CDN reciters, duration per ayah can be fetched from cached audio metadata
  or estimated from average ayah length; for local recordings, use actual
  segment durations
- Update the estimate live as the user changes range, repeats, or speed

**Scope**: Small — compute a sum from existing duration data and display it.
No new models or services needed.

---

## TIL-3. Bismillah Before Each Surah (Except Tawbah)

**Problem**
When playing a surah from the beginning, there is no Bismillah recited before it.
Most masahif and traditional recitations include the Bismillah before every surah
except At-Tawbah (Surah 9), which begins without one.

**What's needed**
- Before playing the first ayah of any surah (except Surah 9), automatically
  prepend the Bismillah audio
- Source the Bismillah audio from the reciter's Fatiha (1:1) segment — this
  avoids needing a separate Bismillah file per reciter
- Make this behaviour toggleable in playback settings (default: on)

**Scope**: Small — playback queue insertion logic + a setting toggle. No new
audio files needed.

---

## TIL-4. Add Haptic Feedback

**Problem**
The app has no tactile feedback. Interactions like page turns, playback
controls, marker placement, and navigation feel flat without haptics.

**What's needed**
- Add `UIImpactFeedbackGenerator` / `UISelectionFeedbackGenerator` haptics to
  key interactions: page swipes, play/pause, ayah marker placement, picker
  selections, and destructive confirmations
- Use appropriate feedback styles (light for selections, medium for actions,
  heavy/notification for errors or completions)
- Make haptics toggleable in settings (default: on)

**Scope**: Small — sprinkle `UIFeedbackGenerator` calls at existing interaction
points. No architectural changes.

---

## TIL-5. Re-enable Warsh/Qaloon in Riwayah Compat Builder

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

## TIL-6. Fuzzy Search Ayah Text in Jump-to Menu

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

## TIL-8. Displaying Masahif for Non-Hafs Riwayahs

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
TIL-5 is done. Requires a decision on the Unicode rendering approach before
Swift model changes.

---

## TIL-9. Horizontal Two-Page Landscape Layout

**Problem**
In landscape orientation the app still shows a single mushaf page, wasting half
the screen. Traditional mushaf reading uses a two-page spread, and e-readers
like Kindle already offer this experience.

**What's needed**
- Detect landscape orientation and display two consecutive mushaf pages
  side-by-side (right-to-left: odd page on the right, even on the left)
- Swipe interaction should animate as a page flip (similar to Kindle's page-turn
  effect) rather than a simple scroll
- Ensure highlighting, navigation, and playback tracking work correctly across
  the two-page spread
- Graceful fallback to single-page on smaller screens (iPhone landscape) where
  two pages would be too cramped

**Scope**: Large — mushaf layout engine changes, custom page-flip gesture and
animation, and two-page state synchronization.

---

## TIL-10. Compatibility Rethink for Different-Ayah-Count Riwayahs

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
Requires TIL-5 and TIL-8 to be completed first, since they all share the same
underlying alignment model.

---

## TIL-11. Auto-Segment Recordings via Quran Detection

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

## TIL-12. Reciter CDN Import Rework + Admin Review System

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
