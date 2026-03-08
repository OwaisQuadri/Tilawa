#!/usr/bin/env python3
from __future__ import annotations
"""
build_ayah_offset_map.py

Builds a per-position Hafs↔Warsh and Hafs↔Qaloon ayah mapping table using the
KFGQPC dataset, which uses native riwayah-specific ayah numbering.

Algorithm:
  For each surah, align Hafs ayahs with the riwayah ayahs using normalized text
  matching (strip diacritics/vowels for comparison). Handles:
  - Deletions: a Hafs ayah with no equivalent in the riwayah (e.g. Basmala)
  - Splits:    one Hafs ayah that maps to 2+ riwayah ayahs
  - Merges:    multiple Hafs ayahs that merge into 1 riwayah ayah

Output (per riwayah):
  Tilawa/Resources/QuranData/ayah_offset_maps/<riwayah>.json

Format:
  [
    { "hafs_surah": 1, "hafs_ayah": 1, "native_surah": null, "native_ayah": null },  // no equiv
    { "hafs_surah": 1, "hafs_ayah": 2, "native_surah": 1, "native_ayah": 1 },
    ...
  ]

  One entry per Hafs ayah (6236 entries total).
  null native_ayah = this Hafs position has no independent counterpart in that riwayah.

Usage:
    python3 Scripts/build_ayah_offset_map.py [--dry-run]
"""

import json
import os
import re
import sys
import unicodedata
import urllib.request
from collections import defaultdict
from difflib import SequenceMatcher

KFGQPC_BASE = "https://raw.githubusercontent.com/thetruetruth/quran-data-kfgqpc/main"
OUTPUT_DIR = os.path.join(
    os.path.dirname(__file__),
    "..", "Tilawa", "Resources", "QuranData", "ayah_offset_maps"
)

RIWAYAT = {
    "warsh":  f"{KFGQPC_BASE}/warsh/data/warshData_v10.json",
    "qaloon": f"{KFGQPC_BASE}/qaloon/data/QaloonData_v10.json",
}

# ---------------------------------------------------------------------------
# Text normalisation
# ---------------------------------------------------------------------------

# Remove Arabic diacritics (harakat, shadda, etc.) and special chars
_DIACRITICS = re.compile(
    r'[\u0610-\u061A'   # Extended Arabic combining
    r'\u064B-\u065F'   # Harakat (fathatan, kasratan, dammatan, fatha, kasra, damma, sukun, shadda, etc.)
    r'\u0670'           # Arabic letter superscript alef
    r'\u06D6-\u06DC'   # Quranic annotation signs
    r'\u06DF-\u06E4'   # More annotation signs
    r'\u06E7-\u06E8'   # Quranic marks
    r'\u06EA-\u06ED'   # More marks
    r'\u0640'           # Tatweel
    r'\u200C-\u200F'   # Zero-width chars
    r'\uFEFF'           # BOM
    r']'
)
_TRAILING_AYA = re.compile(r'[\u0660-\u0669\d\s\xa0]+$')  # Arabic-Indic digits + number sign
_SPACES = re.compile(r'\s+')

# Normalize alef variants and waw/ya variants
_ALEF_MAP = {ord(c): 'ا' for c in 'أإآٱٲٳٴ'}  # normalize alef variants
_WAW = str.maketrans('ٶ', 'و')

def normalize(text: str) -> str:
    if not text:
        return ""
    text = unicodedata.normalize('NFC', text)
    text = _TRAILING_AYA.sub('', text)
    text = _DIACRITICS.sub('', text)
    text = text.translate(_ALEF_MAP)
    text = text.translate(_WAW)
    text = _SPACES.sub(' ', text).strip()
    return text


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

def fetch_json(url: str) -> list[dict]:
    print(f"  Fetching {url.split('/')[-1]}...", end=" ", flush=True)
    with urllib.request.urlopen(url, timeout=60) as r:
        data = json.loads(r.read().decode())
    print(f"{len(data)} ayahs")
    return data


def build_surah_dict(rows: list[dict]) -> dict[int, list[tuple]]:
    """Returns {surah_no: [(aya_no, normalized_text), ...]} sorted by aya_no."""
    d: dict[int, list] = defaultdict(list)
    for row in rows:
        sura = int(row.get('sura_no') or row.get('sora'))
        aya = int(row['aya_no'])
        text = normalize(row.get('aya_text') or '')
        d[sura].append((aya, text))
    for sura in d:
        d[sura].sort()
    return d


# ---------------------------------------------------------------------------
# Alignment algorithm
# ---------------------------------------------------------------------------

def text_similarity(a: str, b: str) -> float:
    if not a or not b:
        return 0.0
    return SequenceMatcher(None, a, b).ratio()


def word_set(text: str) -> set:
    """Split normalized text into word tokens for Jaccard similarity."""
    return set(text.split()) if text else set()


def jaccard(a: str, b: str) -> float:
    """Jaccard similarity on word sets. More robust than SequenceMatcher for Arabic."""
    sa, sb = word_set(a), word_set(b)
    if not sa and not sb:
        return 1.0
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / len(sa | sb)


def align_surah(hafs_ayahs: list, riwayah_ayahs: list) -> list:
    """
    Global (Needleman-Wunsch) alignment of Hafs ayahs against riwayah ayahs.

    Returns a list of length len(hafs_ayahs).
    Each element is either:
      - int  : the native riwayah ayah number this Hafs ayah corresponds to
      - None : no native equivalent (e.g. the Basmala in surah 1 for Warsh)

    Handles merges (1 riwayah = 2+ hafs ayahs) and splits (1 hafs = 2+ riwayah ayahs)
    by mapping each Hafs position to the FIRST riwayah ayah of the corresponding block.
    """
    H = len(hafs_ayahs)
    R = len(riwayah_ayahs)

    if H == 0:
        return []
    if R == 0:
        return [None] * H

    GAP = -0.25  # penalty for each unmatched (null) ayah

    # dp[i][j] = best alignment score for hafs[:i] vs riwayah[:j]
    # back[i][j] = traceback: 'M' match, 'H' delete hafs (null), 'R' skip riwayah
    INF = float('-inf')
    dp = [[INF] * (R + 1) for _ in range(H + 1)]
    back = [[''] * (R + 1) for _ in range(H + 1)]

    dp[0][0] = 0.0
    for i in range(1, H + 1):
        dp[i][0] = i * GAP
        back[i][0] = 'H'
    for j in range(1, R + 1):
        dp[0][j] = j * GAP
        back[0][j] = 'R'

    for i in range(1, H + 1):
        h_no, h_text = hafs_ayahs[i - 1]
        for j in range(1, R + 1):
            r_no, r_text = riwayah_ayahs[j - 1]

            # Match: align hafs[i-1] with riwayah[j-1]
            sim = jaccard(h_text, r_text)
            score_match = dp[i - 1][j - 1] + sim

            # Delete hafs[i-1] (null mapping — no riwayah equivalent)
            score_del = dp[i - 1][j] + GAP

            # Skip riwayah[j-1] (riwayah has an ayah Hafs doesn't)
            score_skip = dp[i][j - 1] + GAP

            best = max(score_match, score_del, score_skip)
            dp[i][j] = best

            if best == score_match:
                back[i][j] = 'M'
            elif best == score_del:
                back[i][j] = 'H'
            else:
                back[i][j] = 'R'

    # Traceback
    result = [None] * H
    i, j = H, R
    while i > 0 or j > 0:
        b = back[i][j]
        if b == 'M':
            result[i - 1] = riwayah_ayahs[j - 1][0]
            i -= 1
            j -= 1
        elif b == 'H':
            result[i - 1] = None   # hafs ayah deleted (no riwayah equivalent)
            i -= 1
        else:  # 'R'
            j -= 1  # riwayah ayah skipped (no hafs equivalent)

    return result


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    dry_run = "--dry-run" in sys.argv

    # Load Hafs KFGQPC data
    print("Loading KFGQPC data...")
    hafs_url = f"{KFGQPC_BASE}/hafs/data/hafsData_v18.json"
    hafs_data = fetch_json(hafs_url)
    hafs_surahs = build_surah_dict(hafs_data)

    if not dry_run:
        os.makedirs(OUTPUT_DIR, exist_ok=True)

    for riwayah, url in RIWAYAT.items():
        print(f"\nProcessing {riwayah}...")
        riwayah_data = fetch_json(url)
        riwayah_surahs = build_surah_dict(riwayah_data)

        output = []
        null_count = 0
        mismatch_count = 0

        for surah_no in range(1, 115):
            h_ayahs = hafs_surahs.get(surah_no, [])
            r_ayahs = riwayah_surahs.get(surah_no, [])

            alignment = align_surah(h_ayahs, r_ayahs)

            for (h_no, h_text), r_match in zip(h_ayahs, alignment):
                if r_match is None:
                    output.append({
                        "hafs_surah": surah_no,
                        "hafs_ayah": h_no,
                        "native_surah": None,
                        "native_ayah": None,
                    })
                    null_count += 1
                else:
                    output.append({
                        "hafs_surah": surah_no,
                        "hafs_ayah": h_no,
                        "native_surah": surah_no,
                        "native_ayah": r_match,
                    })

        print(f"  -> {len(output)} entries, {null_count} Hafs ayahs with no native equivalent")

        # Quick sanity check: surah 1
        s1 = [e for e in output if e['hafs_surah'] == 1]
        print(f"  Surah 1 mapping (first 4):")
        for e in s1[:4]:
            print(f"    Hafs 1:{e['hafs_ayah']} → {e['native_surah']}:{e['native_ayah']}")

        if not dry_run:
            out_path = os.path.join(OUTPUT_DIR, f"ayah_offset_{riwayah}.json")
            with open(out_path, 'w', encoding='utf-8') as f:
                json.dump(output, f, ensure_ascii=False, separators=(',', ':'))
            kb = os.path.getsize(out_path) / 1024
            print(f"  Written: {out_path} ({kb:.0f} KB)")

    print("\nDone.")


if __name__ == "__main__":
    main()
