# Backlogged Tasks

Deferred work, sorted by ROI (value ÷ effort). Items near the top deliver the
most impact for the least work.

**Next available ticket ID: TIL-22**

| # | Task | Scope |
|---|------|-------|
| TIL-3 | [Bismillah Before Each Surah (Except Tawbah)](#til-3-bismillah-before-each-surah-except-tawbah) | Small |
| TIL-4 | [Add Haptic Feedback](#til-4-add-haptic-feedback) | Small |
| TIL-7 | [Finalize Should Strip Audio Between Ayah Segments](#til-7-finalize-should-strip-audio-between-ayah-segments) | Moderate |
| TIL-8 | [Displaying Masahif for Non-Hafs Riwayahs](#til-8-displaying-masahif-for-non-hafs-riwayahs) | Large |
| TIL-9 | [Horizontal Two-Page Landscape Layout](#til-9-horizontal-two-page-landscape-layout) | Large |
| TIL-10 | [Compatibility Rethink for Different-Ayah-Count Riwayahs](#til-10-compatibility-rethink-for-different-ayah-count-riwayahs) | Large |
| TIL-11 | [Auto-Segment Recordings via Quran Detection](#til-11-auto-segment-recordings-via-quran-detection) | Very Large |
| TIL-12 | [Reciter CDN Import Rework + Admin Review System](#til-12-reciter-cdn-import-rework--admin-review-system) | Large |
| TIL-21 | [Similar Verses Discovery](#til-21-similar-verses-discovery) | Medium |
| TIL-20 | [Rule-Based Shatibiyyah Compatibility Engine](#til-20-rule-based-shatibiyyah-compatibility-engine) | Large |

### Parallel work groups

Tasks grouped by file-overlap so each group can run on its own branch with
minimal merge conflicts. Work any **one task per group** at a time; groups
themselves are safe to run in parallel.

| Group | Tasks | Key files touched |
|-------|-------|-------------------|
| A — Jump-to sheet | TIL-21 | `JumpToAyahSheet`, `ArabicTextSearchService` |
| B — Playback engine | TIL-3 | `PlaybackSetupSheet`, `PlaybackQueue`, `PlaybackEngine`, `PlaybackSettings` |
| C — CDN / Library UI | TIL-12 | `RecitersView`, `ReciterDetailView`, CDN views |
| E — Riwayah data | TIL-10, TIL-20 | `Scripts/`, `RiwayahCompatibilityService`, `ReciterResolver` |
| F — Mushaf rendering | TIL-8, TIL-9 | `MushafView`, `MushafPageView`, `MushafViewModel` |
| G — Haptics (do last) | TIL-4 | Touches many views — best merged after other UI work |
| H — ML / R&D | TIL-11 | Mostly new files, independent |

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

### CDN numbering scheme detection

Most Warsh/Qaloon CDNs split audio at **Hafs** ayah boundaries (6236 files), even
though native Warsh numbering has only 6214. The compat builder currently excludes
Warsh/Qaloon at null-offset positions (e.g. 2:1 الم, which Warsh merges into 2:2).
This means the resolver won't try to substitute Warsh CDN audio at those positions,
even though the CDN file actually contains just الم and is perfectly compatible.

To fix this:
- After the availability check (`CDNAvailabilityChecker`), infer the numbering
  scheme by comparing `missingAyahs` against the riwayah's offset map null
  positions. If missing ayahs match the null pattern → native numbering; if all
  6236 are present → Hafs numbering.
- Store the detected scheme on `ReciterCDNSource` (e.g. `numberingScheme: String?`
  — "hafs" or "native").
- In `ReciterResolver`, when resolving a Hafs-numbered Warsh CDN, bypass the
  offset map and use direct Hafs position lookup for compatibility.

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

---

## TIL-20. Rule-Based Shatibiyyah Compatibility Engine

**Problem**
The riwayah compat builder (TIL-5) uses a two-pass approach: consonantal
comparison followed by same-encoding diacritic splitting. Cross-encoding pairs
(hafs↔warsh, hafs↔qaloon) can't be compared diacritically because the KFGQPC
datasets use inconsistent encoding conventions (QPC vs Maghribi). This means
~2853 positions where all 4 riwayahs share consonants may include false
positives — ayahs that sound different due to vowel/pronunciation variants
(imaalah, silah, different harakat) but can't be detected from the text data.

**What's needed**
Encode known qira'at rules from the Shatibiyyah and Durrah to detect
pronunciation differences that don't change the consonantal skeleton:

- **Usul (general rules)**: imaalah positions, silat ha al-dameer, silat meem
  al-jam', naql, ibdal, taqleel, idgham patterns, madd differences
- **Farsh al-huruf (specific words)**: ~500+ word-level variants per qari,
  documented per surah in the Shatibiyyah

For each rule, apply it as a post-processing splitter: if a Shatibiyyah rule
says Warsh reads a word differently from Hafs at position X, and they're
currently in the same compatibility group, split them.

**Dependency**
TIL-5 must be done first (provides the base compatibility draft).

**Scope**: Large — requires scholarly input to catalog and encode the rules,
plus careful validation. The usul are finite and systematic; the farsh are
numerous but well-documented in traditional sources.

---

## TIL-21. Similar Verses Discovery

**Problem**
Many ayahs in the Quran share similar phrasing. Users studying or memorizing
often want to find related verses but have no way to discover them from the
current page.

**What's needed**
- A "Similar Verses" feature accessible from the ayah context or search results
- Compare ayah text using the existing `ArabicTextSearchService` stripped index
  (consonantal skeleton similarity)
- Rank by text overlap (e.g. longest common substring or edit distance on
  stripped text)
- Present results in a sheet or inline list with snippets and navigation

**Scope**: Medium — builds on the search index from TIL-6. Needs a similarity
algorithm and UI, but no new data sources.
