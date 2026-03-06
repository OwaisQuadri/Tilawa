#!/usr/bin/env python3
"""
riwayah_compat_builder.py

Downloads Quran text for hafs + shuabah from the KFGQPC dataset
(github.com/thetruetruth/quran-data-kfgqpc) and generates
Scripts/riwayah_compat_draft.json based on textual identity at each ayah.

The remaining 18 riwayahs are left as strict singletons.
Use riwayah_compat_editor.py to fill those in manually, then deploy from there.

Usage:
    python3 Scripts/riwayah_compat_builder.py [--dry-run | -h]

    --dry-run   Print stats without writing to disk.
"""

import json
import os
import re
import sys
import urllib.request
from collections import defaultdict

SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DRAFT_JSON   = os.path.join(SCRIPT_DIR, "riwayah_compat_draft.json")
APP_JSON     = os.path.join(PROJECT_ROOT, "Tilawa/Resources/riwayah_compatibility.json")

BASE_URL = "https://raw.githubusercontent.com/thetruetruth/quran-data-kfgqpc/main"

# Only riwayahs with the same 6236-ayah Hafs numbering are safe for direct
# position-by-position comparison. Others (warsh, qaloon, doori, soosi,
# bazzi, qunbul) use a different ayah count and need a per-surah offset
# mapping first — tracked in backlog.md.
SOURCES = {
    "hafs":    f"{BASE_URL}/hafs/data/hafsData_v18.json",
    "shuabah": f"{BASE_URL}/shouba/data/ShoubaData08.json",
}

# Canonical order from riwayah_compat_editor.py
ALL_20 = [
    "hafs", "shuabah", "warsh", "qaloon", "bazzi", "qunbul",
    "doori_abu_amr", "soosi", "hisham", "ibn_dhakwan",
    "khalaf_an_hamza", "khallad", "abul_harith", "doori_al_kisai",
    "ibn_wardan", "ibn_jammaz", "ruways", "rawh", "ishaq", "idris",
]
UNVERIFIED = [r for r in ALL_20 if r not in SOURCES]


# Arabic-Indic digits + Western digits, used as embedded verse numbers in some datasets
_TRAILING_DIGITS = re.compile(r"[\u0660-\u0669\d\s]+$")


def fetch_json(url):
    name = url.split("/")[-1]
    print(f"  Fetching {name}...", end=" ", flush=True)
    with urllib.request.urlopen(url, timeout=30) as r:
        data = json.loads(r.read().decode())
    print(f"{len(data)} ayahs")
    return data


def normalize_text(text):
    """Strip trailing embedded verse numbers and whitespace for comparison."""
    if not text:
        return ""
    return _TRAILING_DIGITS.sub("", text).strip()


def get_row_key(row):
    """Return (sura, aya) regardless of which field name the dataset uses."""
    sura = row.get("sora") or row.get("sura_no")
    return (int(sura), int(row["aya_no"]))


HELP = """
riwayah_compat_builder.py — Generate riwayah compatibility draft from KFGQPC text data

USAGE
    python3 Scripts/riwayah_compat_builder.py [OPTIONS]

OPTIONS
    (no args)    Download text for 8 riwayahs, compare per-ayah, write draft
    --dry-run    Run comparison and print stats without writing anything to disk
    -h, --help   Show this help

WORKFLOW
    1. python3 Scripts/riwayah_compat_builder.py          # build draft
    2. python3 Scripts/riwayah_compat_editor.py           # review/edit draft
    3. python3 Scripts/riwayah_compat_editor.py --deploy  # push to app

FILES
    Draft (safe to edit):  Scripts/riwayah_compat_draft.json
    App (prod, do not touch directly): Tilawa/Resources/riwayah_compatibility.json

RIWAYAHS COVERED (2/20 — same 6236-ayah numbering as Hafs, safe to compare)
    hafs, shuabah

RIWAYAHS REQUIRING MANUAL ENTRY (18/20 — use editor with recordings)
    warsh, qaloon, bazzi, qunbul, doori_abu_amr, soosi,
    hisham, ibn_dhakwan, khalaf_an_hamza, khallad, abul_harith, doori_al_kisai,
    ibn_wardan, ibn_jammaz, ruways, rawh, ishaq, idris

    Note: warsh, qaloon, bazzi, qunbul, doori_abu_amr, soosi have KFGQPC text
    data available but use a different ayah numbering — needs offset mapping
    before they can be auto-compared. See backlog.md.
"""


def main():
    dry_run = "--dry-run" in sys.argv

    if "-h" in sys.argv or "--help" in sys.argv:
        print(HELP)
        return

    # ── Load text data ────────────────────────────────────────────────────────
    texts = {}  # {riwayah: {(sura, aya_no): aya_text}}
    print("Downloading riwayah text data from KFGQPC...")
    for riwayah, url in SOURCES.items():
        rows = fetch_json(url)
        texts[riwayah] = {
            get_row_key(row): normalize_text(row.get("aya_text") or "")
            for row in rows
        }

    # ── Collect all positions ─────────────────────────────────────────────────
    all_positions = set()
    for ayah_map in texts.values():
        all_positions.update(ayah_map.keys())
    all_positions = sorted(all_positions)
    print(f"\nTotal unique (sura, ayah) positions: {len(all_positions)}")

    # ── Build compatibility groups ────────────────────────────────────────────
    output = []
    n_all_same = 0
    n_split = 0

    for (sura, aya_no) in all_positions:
        # Group verified riwayahs by identical aya_text
        text_to_riwayahs: dict[str, list] = defaultdict(list)
        for riwayah in SOURCES:
            text = texts[riwayah].get((sura, aya_no))
            if text is not None:
                text_to_riwayahs[text].append(riwayah)

        # Sort groups canonically by first member's position in ALL_20
        data_groups = sorted(
            [sorted(rws, key=ALL_20.index) for rws in text_to_riwayahs.values()],
            key=lambda g: ALL_20.index(g[0])
        )

        if len(data_groups) == 1:
            n_all_same += 1
        else:
            n_split += 1

        # Unverified riwayahs are strict singletons — manual review needed
        groups = data_groups + [[r] for r in UNVERIFIED]

        output.append({"surah": sura, "ayah": aya_no, "groups": groups})

    # ── Print summary ─────────────────────────────────────────────────────────
    print(f"\nResults across {len(output)} ayahs:")
    print(f"  All 8 verified riwayahs identical: {n_all_same}")
    print(f"  Has textual differences:           {n_split}")
    print(f"  Unverified (still strict):         {UNVERIFIED}")

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
