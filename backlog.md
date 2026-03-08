# Backlogged Tasks

Deferred work that is too large or too dependent on future decisions.

---

## 1. Re-enable Warsh/Qaloon in Riwayah Compat Builder

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

## 2. Displaying Masahif for Non-Hafs Riwayahs

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
Task 1 is done. Requires a decision on the Unicode rendering approach before
Swift model changes.

---

## 3. Compatibility Rethink for Different-Ayah-Count Riwayahs

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
Requires tasks 1 and 2 to be completed first, since they all share the same
underlying alignment model.
