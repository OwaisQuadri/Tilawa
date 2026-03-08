#!/usr/bin/env python3
"""
fetch_riwayah_text.py

Downloads Quranic ayah text for multiple riwayat from the fawazahmed0/quran-api
GitHub repository and converts them to app-compatible JSON files.

Output format (per riwayah):
{
  "riwayah": "warsh",
  "surahs": [
    ["ayah1text", "ayah2text", ...],   // surah 1 — 0-indexed (ayah 1 = index 0)
    ["ayah1text", ...],                 // surah 2
    ...                                 // 114 total
  ]
}

Usage:
    python3 Scripts/fetch_riwayah_text.py [--dry-run]
"""

import json
import os
import sys
import urllib.request

BASE_URL = "https://raw.githubusercontent.com/fawazahmed0/quran-api/1/editions/"
OUTPUT_DIR = os.path.join(
    os.path.dirname(__file__),
    "..", "Tilawa", "Resources", "QuranData", "riwayah_text"
)

# Map from app Riwayah rawValue -> edition filename (without .json)
EDITIONS = {
    "hafs":           "ara-quranuthmanihaf",
    "shuabah":        "ara-quranshouba",
    "warsh":          "ara-quranwarsh",
    "qaloon":         "ara-quranqaloon",
    "doori_abu_amr":  "ara-qurandoori",
    "soosi":          "ara-quransoosi",
}

EXPECTED_SURAHS = 114


def fetch_edition(edition_id: str) -> list[dict]:
    """Download and parse an edition JSON from GitHub. Returns list of verse dicts."""
    url = BASE_URL + edition_id + ".json"
    print(f"  Fetching {url}...")
    with urllib.request.urlopen(url, timeout=30) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    verses = data.get("quran") or data.get("verses") or data.get("data") or []
    if not verses:
        raise ValueError(f"No verses found in {edition_id}. Top-level keys: {list(data.keys())}")
    return verses


def convert_to_surah_arrays(verses: list[dict]) -> list[list[str]]:
    """
    Convert flat verse list to nested array: surahs[surahIndex][ayahIndex]
    Both indices are 0-based (surah 1 = index 0, ayah 1 = index 0).
    """
    surahs: list[list[str]] = []
    current_surah = 0

    for verse in verses:
        chapter = int(verse["chapter"])
        text = verse["text"].strip()

        # Fill any skipped surahs (shouldn't happen but guard defensively)
        while len(surahs) < chapter:
            surahs.append([])

        surahs[chapter - 1].append(text)
        current_surah = chapter

    if len(surahs) != EXPECTED_SURAHS:
        print(f"    WARNING: Expected {EXPECTED_SURAHS} surahs, got {len(surahs)}")

    return surahs


def build_output(riwayah: str, surahs: list[list[str]]) -> dict:
    total_ayahs = sum(len(s) for s in surahs)
    return {
        "riwayah": riwayah,
        "total_ayahs": total_ayahs,
        "surahs": surahs,
    }


def main():
    dry_run = "--dry-run" in sys.argv

    if not dry_run:
        os.makedirs(OUTPUT_DIR, exist_ok=True)

    for riwayah, edition_id in EDITIONS.items():
        print(f"\nProcessing {riwayah} ({edition_id})...")
        try:
            verses = fetch_edition(edition_id)
            surahs = convert_to_surah_arrays(verses)
            output = build_output(riwayah, surahs)

            total = output["total_ayahs"]
            print(f"  -> {len(surahs)} surahs, {total} total ayahs")

            if not dry_run:
                out_path = os.path.join(OUTPUT_DIR, f"riwayah_text_{riwayah}.json")
                with open(out_path, "w", encoding="utf-8") as f:
                    json.dump(output, f, ensure_ascii=False, separators=(",", ":"))
                size_kb = os.path.getsize(out_path) / 1024
                print(f"  Written: {out_path} ({size_kb:.0f} KB)")

        except Exception as e:
            print(f"  ERROR for {riwayah}: {e}", file=sys.stderr)

    print("\nDone.")


if __name__ == "__main__":
    main()
