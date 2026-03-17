# Known Bugs

Tracked bugs to fix in future releases.

| ID | Summary | Status |
|----|---------|--------|
| BUG-1 | [Play modal doesn't show union of selectable surahs across sources](#bug-1-play-modal-doesnt-show-union-of-selectable-surahs-across-sources) | Open |

---

## BUG-1: Play modal doesn't show union of selectable surahs across sources

**Status**: Open

**Summary**: When a reciter has both manually segmented recordings and a CDN source, the play modal only shows the manually segmented surahs as selectable — it should show the union of both.

**Repro**:
1. Have a reciter with Fatiha + Baqarah in manual segments and Maryam on CDN
2. Open the play modal and select that reciter
3. Only Fatiha and Baqarah are selectable

**Expected**: Fatiha, Baqarah, and Maryam should all be selectable.

**Root cause**: In `PlaybackSetupSheet.swift`, `cdnAvailableAyahs()` returns `nil` when the CDN source hasn't had its availability checked yet (`availabilityChecked == false`). The `availableAyahs()` union logic then falls back to returning only local segments.

**Key files**:
- `Tilawa/Views/Player/PlaybackSetupSheet.swift` — `cdnAvailableAyahs()`, `availableAyahs()`
