# Tilawa — Product Requirements Document

**Version:** 1.0
**Platform:** iOS 17+
**App Name:** Tilawa (تلاوة — "recitation")

---

## 1. Product Overview

Tilawa is a personal Quran recitation companion that combines a traditional Mushaf reader with a UGC-first audio player. The central differentiator: your own recordings of live recitations become first-class citizens in the playback priority queue, automatically replacing or supplementing professional reciter audio for the ayaat you've personally collected.

**Core value proposition:** Every recording from every halaqa, Friday prayer, or personal session you've ever attended — organized, tagged to exact ayaat, and seamlessly woven into your daily recitation routine.

---

## 2. User Personas

### Persona A — The Hifz Student
- **Age:** 15–35
- **Goal:** Memorize surahs by listening to their teacher's recordings with precise loop control. Wants to hear only the specific ayaat being worked on, repeatedly.
- **Pain points:** Existing apps have no support for personal recordings. Loop controls are too coarse (whole surah only). Can't isolate individual ayaat from a teacher recording.

### Persona B — The Imam / Advanced Reciter
- **Age:** 25–60
- **Goal:** Review live recording of their Friday prayer khutbah recitation alongside a professional reciter for quality comparison. Wants to reference specific moments from halaqas they attended years ago.
- **Pain points:** Recordings scattered in Voice Memos with no ayah metadata. No A/B comparison between their recitation and a professional. No timeline of their recitation journey.

### Persona C — The Riwayah Student
- **Age:** 20–50
- **Goal:** Study multiple riwayahs (Hafs, Warsh, Qaloon) with full control over reciter priority. Wants to hear their teacher's Warsh recitation first, falling back to a known professional Warsh reciter when gaps exist.
- **Pain points:** No app supports riwayah-aware multi-reciter priority queues. No intelligent fallback without manually switching apps.

---

## 3. Feature Requirements

### F1: Mushaf Display

| ID | Requirement | Priority |
|----|-------------|----------|
| F1.1 | Display Al Madinah Mushaf style pages (604 pages) | P0 |
| F1.2 | Word-by-word highlighting synced to current audio position | P0 |
| F1.3 | Ayah-level highlighting as fallback when word timing unavailable | P0 |
| F1.4 | Page-turn navigation (swipe left/right) | P0 |
| F1.5 | Jump to surah/ayah via search or index | P0 |
| F1.6 | Persistent overlay: current repetition count (e.g., "Rep 3/5") | P1 |
| F1.7 | Persistent overlay: active reciter name and riwayah | P1 |
| F1.8 | Tap an ayah to jump playback to that ayah | P1 |
| F1.9 | Night mode / sepia mode rendering | P2 |
| F1.10 | Font size adjustment for non-image rendering | P2 |

### F2: Playback Engine

| ID | Requirement | Priority |
|----|-------------|----------|
| F2.1 | Play / pause / next ayah / previous ayah | P0 |
| F2.2 | Playback speed: 0.5×, 0.75×, 1.0×, 1.25×, 1.5×, 1.75×, 2.0× | P0 |
| F2.3 | Ayah repeat: 1–100 or infinite loop | P0 |
| F2.4 | Range repeat: 1–100 or infinite loop | P0 |
| F2.5 | Start and end verse (or start and end page) selection | P0 |
| F2.6 | "Connection ayah" — include N ayaat before start and/or after end | P1 |
| F2.7 | After finite range repeat: continue with next N ayaat OR next N pages | P1 |
| F2.8 | Background audio (AVAudioSession .playback) | P0 |
| F2.9 | Now Playing integration — lock screen controls, artwork | P0 |
| F2.10 | Remote command: forward = next ayah, back = previous ayah | P0 |
| F2.11 | Riwayah selection: Hafs, Shu3bah, Warsh, Qaloon, Doori, Bazzi | P1 |
| F2.12 | Multi-reciter ordered priority list (drag to reorder) | P1 |
| F2.13 | Auto-fallback to next available reciter when preferred is missing | P1 |
| F2.14 | Configurable silent gap between ayaat (0–3000 ms) | P2 |
| F2.15 | Basmallah handling per surah start (include/exclude) | P1 |

### F3: UGC Recording System

| ID | Requirement | Priority |
|----|-------------|----------|
| F3.1 | Import audio from Files app (mp3, m4a, wav, caf) | P0 |
| F3.2 | Import audio from Voice Memos | P1 |
| F3.3 | Record directly in-app using microphone | P1 |
| F3.4 | Waveform visualization of imported/recorded audio | P0 |
| F3.5 | Tap waveform to place ayah boundary markers | P0 |
| F3.6 | Auto-suggest segment boundaries using silence detection | P1 |
| F3.7 | Assign surah:ayah to each annotated segment | P0 |
| F3.8 | Support cross-surah segments (e.g., Anfal 8:75 → Tawbah 9:1) | P1 |
| F3.9 | Library: browse all recordings by surah/ayah coverage | P0 |
| F3.10 | Recordings appear in reciter priority list as first-class reciters | P0 |
| F3.11 | Auto-switch to personal recording when available for current ayah | P0 |
| F3.12 | iCloud sync of recordings and annotations via ubiquity container | P1 |
| F3.13 | Edit annotations after initial tagging | P1 |
| F3.14 | Delete recordings or individual segments | P1 |

### F4: Settings & Preferences

| ID | Requirement | Priority |
|----|-------------|----------|
| F4.1 | Persist global default playback settings to SwiftData | P0 |
| F4.2 | Per-session override without permanently changing defaults | P1 |
| F4.3 | Reciter library: browse, add, remove named reciters | P0 |
| F4.4 | Download management for offline reciter audio | P1 |
| F4.5 | Translation/tafsir overlay | P2 |

---

## 4. User Stories

### Epic: First-Time Setup
- As a new user, I can select my riwayah (e.g., Hafs) so that all default reciter suggestions match my tradition.
- As a new user, I can choose from a curated list of popular reciters for my riwayah so I have audio without uploading anything.

### Epic: Daily Recitation
- As a user, I open the app to the last page I was reading so I can continue without re-navigating.
- As a user, I tap any ayah on the Mushaf to start playback from that ayah.
- As a user, I set a start and end ayah range to loop 5 times so I can focus on a specific passage.
- As a user, I hear a "connection ayah" before my range to give me melodic context before the loop begins.

### Epic: Hifz / Memorization
- As a hifz student, I loop a single ayah 10 times before the player automatically advances so I memorize one at a time.
- As a hifz student, the screen always shows the current repetition count (e.g., "Rep 7/10") so I never lose count.
- As a hifz student, I set speed to 0.75× so I can follow along and correct my pronunciation.
- As a hifz student, after 5 repetitions of my range, the app automatically advances to the next 5 ayaat so I can do a full-page hifz session hands-free.

### Epic: Recording Upload & Annotation
- As a user, I import an audio file of my teacher's recitation from Files so I can use it in playback.
- As a user, the app auto-suggests silence-based ayah breaks in my recording so annotation is fast.
- As a user, I drag markers on the waveform to fine-tune ayah boundaries so the splits are precise.
- As a user, while assigning an ayah to a segment, the app plays that segment on loop so I can verify which ayah it is by ear.
- As a user, I mark a segment as cross-surah (e.g., Anfal end into Tawbah start) and set exactly where the surah transition occurs within the audio.

### Epic: Playback with Personal Recordings
- As a user, when I play Surah Al-Baqarah and have a personal recording covering ayaat 1–20, the app plays my recording for those ayaat and seamlessly switches to a professional reciter for the rest.
- As a user, an on-screen badge shows which source is playing (personal recording name or professional reciter).
- As a user, I see which recitation source is used per ayah in the playback queue before I press play.

---

## 5. Acceptance Criteria

### AC-1: Ayah Repeat
- Given ayah repeat count = 3 and range repeat = 1, when an ayah finishes the 3rd time, the engine advances to the next ayah without user interaction.
- The repeat counter badge updates immediately after each completion (not at the end of the gap).
- Infinite loop mode does not cause memory growth over time.

### AC-2: Range Repeat with Continuation
- Given range = Al-Baqarah 1–10, rangeRepeat = 5, afterRepeat = "continue next 10 ayaat," when all 5 repetitions complete, playback automatically continues from Al-Baqarah 11–20 at the same ayah repeat count.
- If rangeRepeat = infinite, the "continue" setting is disabled in the UI (greyed out, with explanation).

### AC-3: Reciter Auto-Switch
- Given priority [Personal Recordings, Sheikh A, Sheikh B], when the engine needs ayah X:Y:
  - If Personal Recordings has a matching manually-annotated segment → play it.
  - If no personal segment → play Sheikh A's file if available locally.
  - If Sheikh A is not cached → try Sheikh B.
  - If none available → silent gap + UI indicator "No audio available."

### AC-4: Annotation Auto-Detect
- Given a 10-minute audio file, when the user taps "Auto-detect boundaries," results appear within 5 seconds.
- Suggested markers are shown in a distinct color (unconfirmed) separate from confirmed markers.
- The user can drag each marker to fine-tune position within ±50ms precision on the waveform.

### AC-5: Cross-Surah Segment
- Given a segment tagged as cross-surah (Anfal 8:75 → Tawbah 9:1), when the engine resolves ayah 8:75, it plays from segment start to `crossSurahJoinOffset`. When it resolves 9:1, it plays from `crossSurahJoinOffset` to segment end.

### AC-6: Missing Ayah Handling
- Given a range where ayah 3:45 has no available audio from any reciter, when the user taps play, a non-blocking sheet appears listing the unavailable ayaat with "Continue anyway?" and "Fill from any reciter" options.
- During playback, unavailable ayaat produce a 500ms minimum silence and the Mushaf briefly highlights the ayah in amber.

---

## 6. Out of Scope (v1)
- Monetization, subscriptions, in-app purchases
- Social sharing or community features
- Tafsir or translation display (P2, deferred)
- Android, web, or macOS versions
- AI-based recitation correction or feedback
- Server-side reciter audio hosting (users bring their own or configure existing CDN URLs)
