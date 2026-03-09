#!/usr/bin/env python3
"""
riwayah_compat_builder.py

Downloads Quran text for hafs, shuabah, warsh, and qaloon from the KFGQPC
dataset (github.com/thetruetruth/quran-data-kfgqpc) and generates
Scripts/riwayah_compat_draft.json based on textual comparison at each ayah.

Uses a two-pass approach:
  Pass 1 — Consonantal grouping: strip diacritics (except superscript alef)
           and normalise encoding variants across datasets.
  Pass 2 — Same-encoding diacritic splitting: within each consonantal group,
           split riwayahs that share the same KFGQPC encoding family but have
           different diacritics (these are genuine reading differences).

Warsh and Qaloon use a different ayah numbering (6214 vs Hafs's 6236), so
their text is looked up via bundled offset maps before comparison.

The remaining 16 riwayahs are left as strict singletons.
Use riwayah_compat_editor.py to fill those in manually, then deploy from there.

Usage:
    python3 Scripts/riwayah_compat_builder.py [--dry-run | -h]

    --dry-run   Print stats without writing to disk.
"""

import json
import os
import re
import sys
import unicodedata
import urllib.request
from collections import defaultdict

SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DRAFT_JSON   = os.path.join(SCRIPT_DIR, "riwayah_compat_draft.json")
APP_JSON     = os.path.join(PROJECT_ROOT, "Tilawa/Resources/riwayah_compatibility.json")
OFFSET_DIR   = os.path.join(PROJECT_ROOT, "Tilawa/Resources/QuranData/ayah_offset_maps")

BASE_URL = "https://raw.githubusercontent.com/thetruetruth/quran-data-kfgqpc/main"

# Hafs and shuabah share the 6236-ayah numbering and can be compared directly.
# Warsh and qaloon use a different count (6214) and are compared via offset maps.
SOURCES = {
    "hafs":    f"{BASE_URL}/hafs/data/hafsData_v18.json",
    "shuabah": f"{BASE_URL}/shouba/data/ShoubaData08.json",
    "warsh":   f"{BASE_URL}/warsh/data/warshData_v10.json",
    "qaloon":  f"{BASE_URL}/qaloon/data/QaloonData_v10.json",
}

# Riwayahs that need offset maps to translate Hafs positions to native ayah numbers.
OFFSET_RIWAYAT = {"warsh", "qaloon"}

# KFGQPC encoding families — diacritic comparison is only reliable within a family.
# Cross-family diacritics are inconsistent (different sukoon chars, missing shadda, etc.).
ENCODING_FAMILIES = [
    {"hafs", "shuabah"},     # QPC encoding
    {"warsh", "qaloon"},     # Maghribi encoding
]

# Canonical order from riwayah_compat_editor.py
ALL_20 = [
    "hafs", "shuabah", "warsh", "qaloon", "bazzi", "qunbul",
    "doori_abu_amr", "soosi", "hisham", "ibn_dhakwan",
    "khalaf_an_hamza", "khallad", "abul_harith", "doori_al_kisai",
    "ibn_wardan", "ibn_jammaz", "ruways", "rawh", "ishaq", "idris",
]
UNVERIFIED = [r for r in ALL_20 if r not in SOURCES]


# ---------------------------------------------------------------------------
# Text normalisation
# ---------------------------------------------------------------------------

# Pass 1: consonantal normalisation — strip all diacritics except U+0670
# (superscript alef, distinguishes مٰلك maaliki vs ملك maliki) and normalise
# encoding variants across KFGQPC datasets.
_STRIP_MARKS = re.compile(
    r'[\u0610-\u061A'   # Extended Arabic combining
    r'\u064B-\u065F'    # Harakat (fatha, kasra, damma, sukun, shadda, tanwin, etc.)
    r'\u06D6-\u06ED'    # Quranic annotation signs + small marks
    r'\u06E1'           # Small high dotless head of khah (QPC sukoon)
    r'\u0640'           # Tatweel
    r'\u200C-\u200F'    # Zero-width chars
    r'\uFEFF'           # BOM
    r']'
)
# NOTE: U+0670 (superscript alef) is intentionally NOT stripped.
_TRAILING_AYA = re.compile(r'[\u0660-\u0669\d\s\xa0]+$')
_SPACES = re.compile(r'\s+')
_CONSONANT_MAP = str.maketrans({
    '\u0671': '\u0627',  # alef wasla → plain alef
    '\u0623': '\u0627',  # alef + hamza above → plain alef
    '\u0625': '\u0627',  # alef + hamza below → plain alef
    '\u0622': '\u0627',  # alef + maddah → plain alef
    '\u0672': '\u0627',  # alef wavy hamza above
    '\u0673': '\u0627',  # alef wavy hamza below
    '\u0674': '\u0627',  # high hamza
    '\u06D2': '\u0649',  # yeh barree (Warsh) → alef maksura
    '\u0676': '\u0648',  # waw with high hamza → waw
})

# Pass 2: light normalisation for same-encoding comparison — just NFC + strip
# trailing aya numbers. Diacritics are preserved for reliable within-family comparison.
_RAW_TRAILING = re.compile(r'[\u0660-\u0669\d\s\xa0]+$')


def fetch_json(url):
    name = url.split("/")[-1]
    print(f"  Fetching {name}...", end=" ", flush=True)
    with urllib.request.urlopen(url, timeout=30) as r:
        data = json.loads(r.read().decode())
    print(f"{len(data)} ayahs")
    return data


def normalize_consonantal(text):
    """Strip diacritics (except superscript alef) and normalise encoding variants."""
    if not text:
        return ""
    text = unicodedata.normalize('NFC', text)
    text = _TRAILING_AYA.sub('', text)
    text = _STRIP_MARKS.sub('', text)
    text = text.translate(_CONSONANT_MAP)
    text = _SPACES.sub(' ', text).strip()
    return text


def normalize_raw(text):
    """Light normalisation preserving diacritics — for same-encoding comparison."""
    if not text:
        return ""
    text = unicodedata.normalize('NFC', text)
    text = _RAW_TRAILING.sub('', text).strip()
    return text


def get_row_key(row):
    """Return (sura, aya) regardless of which field name the dataset uses."""
    sura = row.get("sora") or row.get("sura_no")
    return (int(sura), int(row["aya_no"]))


def load_offset_map(riwayah):
    """Load a bundled ayah offset map: surahs[surah_idx][hafs_ayah_idx] → native ayah number or None."""
    path = os.path.join(OFFSET_DIR, f"ayah_offset_{riwayah}.json")
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return data["surahs"]


def get_native_ayah(riwayah, sura, aya_no, offset_maps):
    """Translate a Hafs (sura, aya_no) to the native ayah number for this riwayah."""
    if riwayah not in offset_maps:
        return aya_no
    smap = offset_maps[riwayah]
    if sura - 1 < len(smap) and aya_no - 1 < len(smap[sura - 1]):
        return smap[sura - 1][aya_no - 1]  # int or None
    return None


def split_group_by_diacritics(group, sura, aya_no, raw_texts, offset_maps):
    """Split a consonantal group using same-encoding diacritic comparison.

    Riwayahs in the same encoding family are split if their raw (diacritized)
    text differs. Cross-family pairs are kept together (unreliable comparison).
    """
    if len(group) <= 1:
        return [group]

    # Get raw text for each riwayah in the group
    raw = {}
    for r in group:
        native = get_native_ayah(r, sura, aya_no, offset_maps)
        if native is not None:
            raw[r] = raw_texts[r].get((sura, native), "")

    # Union-find for equivalence classes
    parent = {r: r for r in group}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            # Keep canonical order: earlier in ALL_20 is root
            if ALL_20.index(ra) > ALL_20.index(rb):
                ra, rb = rb, ra
            parent[rb] = ra

    # Merge riwayahs that are compatible:
    # - Same encoding family AND same raw text → merge
    # - Different encoding families → merge (can't distinguish, keep together)
    for i, a in enumerate(group):
        for b in group[i + 1:]:
            same_family = any(a in fam and b in fam for fam in ENCODING_FAMILIES)
            if same_family:
                # Only merge if raw diacritized text matches
                if a in raw and b in raw and raw[a] == raw[b]:
                    union(a, b)
            else:
                # Cross-family: can't compare diacritics, keep grouped
                union(a, b)

    # Extract subgroups
    subgroups: dict[str, list] = defaultdict(list)
    for r in group:
        subgroups[find(r)].append(r)

    return sorted(
        [sorted(sg, key=ALL_20.index) for sg in subgroups.values()],
        key=lambda g: ALL_20.index(g[0])
    )


HELP = """
riwayah_compat_builder.py — Generate riwayah compatibility draft from KFGQPC text data

USAGE
    python3 Scripts/riwayah_compat_builder.py [OPTIONS]

OPTIONS
    (no args)    Download text for 4 riwayahs, compare per-ayah, write draft
    --dry-run    Run comparison and print stats without writing anything to disk
    -h, --help   Show this help

WORKFLOW
    1. python3 Scripts/riwayah_compat_builder.py          # build draft
    2. python3 Scripts/riwayah_compat_editor.py           # review/edit draft
    3. python3 Scripts/riwayah_compat_editor.py --deploy  # push to app

FILES
    Draft (safe to edit):  Scripts/riwayah_compat_draft.json
    App (prod, do not touch directly): Tilawa/Resources/riwayah_compatibility.json

COMPARISON
    Pass 1 — Consonantal: strip diacritics (keep superscript alef), normalise
             encoding variants. Groups riwayahs with identical consonantal text.
    Pass 2 — Diacritic split: within each group, split same-encoding-family
             pairs (hafs/shuabah, warsh/qaloon) if their diacritized text differs.
             Cross-family pairs stay grouped (encoding too inconsistent to compare).

RIWAYAHS COVERED (4/20)
    hafs, shuabah  — same 6236-ayah numbering, compared directly
    warsh, qaloon  — different numbering (6214), compared via offset maps

RIWAYAHS REQUIRING MANUAL ENTRY (16/20 — use editor with recordings)
    bazzi, qunbul, doori_abu_amr, soosi,
    hisham, ibn_dhakwan, khalaf_an_hamza, khallad, abul_harith, doori_al_kisai,
    ibn_wardan, ibn_jammaz, ruways, rawh, ishaq, idris

    Note: bazzi, qunbul, doori_abu_amr, soosi have KFGQPC text data available
    but use a different ayah numbering — needs offset mapping before they can
    be auto-compared. See backlog.md.
"""


def main():
    dry_run = "--dry-run" in sys.argv

    if "-h" in sys.argv or "--help" in sys.argv:
        print(HELP)
        return

    # ── Load offset maps for riwayahs with different ayah numbering ──────────
    offset_maps = {}
    for riwayah in OFFSET_RIWAYAT:
        print(f"  Loading offset map for {riwayah}...")
        offset_maps[riwayah] = load_offset_map(riwayah)

    # ── Load text data ────────────────────────────────────────────────────────
    cons_texts = {}  # {riwayah: {(sura, native_aya): consonantal_text}}
    raw_texts = {}   # {riwayah: {(sura, native_aya): lightly_normalised_text}}
    print("Downloading riwayah text data from KFGQPC...")
    for riwayah, url in SOURCES.items():
        rows = fetch_json(url)
        cons_texts[riwayah] = {
            get_row_key(row): normalize_consonantal(row.get("aya_text") or "")
            for row in rows
        }
        raw_texts[riwayah] = {
            get_row_key(row): normalize_raw(row.get("aya_text") or "")
            for row in rows
        }

    # ── Collect all Hafs positions ────────────────────────────────────────────
    all_positions = sorted(cons_texts["hafs"].keys())
    print(f"\nTotal Hafs (sura, ayah) positions: {len(all_positions)}")

    # ── Pass 1: Build consonantal groups ──────────────────────────────────────
    output = []
    n_pass1_same = 0
    n_pass1_split = 0
    n_pass2_splits = 0

    for (sura, aya_no) in all_positions:
        # Group verified riwayahs by identical consonantal text
        text_to_riwayahs: dict[str, list] = defaultdict(list)
        for riwayah in SOURCES:
            native = get_native_ayah(riwayah, sura, aya_no, offset_maps)
            if native is None:
                continue
            text = cons_texts[riwayah].get((sura, native))
            if text is not None:
                text_to_riwayahs[text].append(riwayah)

        # Sort groups canonically
        consonantal_groups = sorted(
            [sorted(rws, key=ALL_20.index) for rws in text_to_riwayahs.values()],
            key=lambda g: ALL_20.index(g[0])
        )

        if len(consonantal_groups) == 1:
            n_pass1_same += 1
        else:
            n_pass1_split += 1

        # ── Pass 2: Split same-encoding pairs by diacritics ──────────────────
        final_groups = []
        for group in consonantal_groups:
            subgroups = split_group_by_diacritics(
                group, sura, aya_no, raw_texts, offset_maps
            )
            if len(subgroups) > 1:
                n_pass2_splits += 1
            final_groups.extend(subgroups)

        # Re-sort after splitting
        final_groups.sort(key=lambda g: ALL_20.index(g[0]))

        # Unverified riwayahs are strict singletons — manual review needed
        groups = final_groups + [[r] for r in UNVERIFIED]
        output.append({"surah": sura, "ayah": aya_no, "groups": groups})

    # ── Print summary ─────────────────────────────────────────────────────────
    print(f"\nResults across {len(output)} ayahs:")
    print(f"  Pass 1 (consonantal):")
    print(f"    All {len(SOURCES)} riwayahs identical:  {n_pass1_same}")
    print(f"    Has consonantal differences:  {n_pass1_split}")
    print(f"  Pass 2 (same-encoding diacritics):")
    print(f"    Groups split by diacritics:   {n_pass2_splits}")
    print(f"  Unverified (still strict):      {len(UNVERIFIED)} riwayahs")

    if dry_run:
        print("\n[dry-run] Not writing to disk.")
        return

    with open(DRAFT_JSON, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"\nWrote {len(output)} entries → {DRAFT_JSON}  (draft, app unchanged)")
    print("Edit with: python3 Scripts/riwayah_compat_editor.py")
    print("Deploy with: python3 Scripts/riwayah_compat_editor.py --deploy")


if __name__ == "__main__":
    main()
