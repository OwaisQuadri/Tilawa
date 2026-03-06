# Backlogged Tasks

Deferred work that is too large or too dependent on future decisions.

---

## 1. Ayah Offset Mapping for Non-Hafs Riwayahs

**Problem**
The KFGQPC dataset has text for 6 more riwayahs (warsh, qaloon, bazzi, qunbul,
doori_abu_amr, soosi) but they use different ayah numbering than Hafs:

| Riwayah       | Ayah count | Offset vs Hafs |
|---------------|------------|----------------|
| warsh, qaloon | 6214       | −22            |
| doori, soosi  | 6217       | −19            |
| bazzi, qunbul | 6220       | −16            |

Directly comparing (sura, aya_no) across these produces wrong pairings (e.g.
Hafs 1:2 Al-Hamd is compared against Warsh 1:2 Ar-Rahman instead of Warsh 1:1).

**What's needed**
A per-surah offset table: for each surah, how many ayahs ahead or behind each
riwayah is relative to Hafs. This lets the builder align positions correctly
before comparing text.

**Then**
Once the offset mapping exists, re-run the builder with those 6 riwayahs
re-enabled in SOURCES and the comparison will be accurate.

---

## 2. Displaying Masahif for Non-Hafs Riwayahs

**Problem**
The app currently renders the Hafs mushaf text for all sessions. If a user
selects Warsh, they hear the Warsh recitation but read the Hafs text — which
may differ at variant positions.

**What's needed**
- Source or license mushaf text for each riwayah (KFGQPC data is available for
  8; others need research)
- Display logic: render the mushaf matching the session's selected riwayah
- Handle different ayah counts: a Warsh mushaf has 6214 ayahs, so the UI
  needs to know which "Hafs ayah number" corresponds to which "Warsh ayah number"
  at each position

**Dependency**
This requires the offset mapping from task 1 above. It also likely requires
Swift model changes (which mushaf text to load, how to navigate across riwayahs).

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
groups, and updating RiwayahCompatibilityService.swift and ReciterResolver.swift
to use them.

**Dependency**
Requires both the offset mapping (task 1) and the mushaf display work (task 2)
to be designed first, since they all share the same underlying alignment model.
