#!/usr/bin/env python3
"""
build_riwayah_metadata.py

Fetches riwayah-specific Quran metadata from the quran-center/quran-meta
GitHub repository and generates per-riwayah metadata JSON files.

For each riwayah, produces:
- Per-surah ayah count (may differ from Hafs)
- Per-surah start page (differs per riwayah mushaf)
- Total page count

Output: Tilawa/Resources/QuranData/riwayah_metadata/<riwayah>.json

Format:
{
  "riwayah": "warsh",
  "totalPages": 604,
  "totalAyahs": 6215,
  "surahs": [
    { "number": 1, "ayahCount": 7, "startPage": 1 },
    ...
  ]
}

Usage:
    python3 Scripts/build_riwayah_metadata.py [--dry-run]
"""

import json
import os
import re
import sys
import urllib.request
import bisect

BASE_URL = "https://raw.githubusercontent.com/quran-center/quran-meta/master/src/lists/"
OUTPUT_DIR = os.path.join(
    os.path.dirname(__file__),
    "..", "Tilawa", "Resources", "QuranData", "riwayah_metadata"
)

RIWAYAT = {
    "hafs":   "HafsLists.ts",
    "warsh":  "WarshLists.ts",
    "qaloon": "QalunLists.ts",
}


def fetch_ts(filename: str) -> str:
    url = BASE_URL + filename
    print(f"  Fetching {url}...")
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.read().decode("utf-8")


def parse_page_list(content: str) -> list[int]:
    """Extract PageList array: each entry is the global ayah ID that starts a page."""
    m = re.search(r"export const PageList: AyahId\[\] = \[(.*?)\]", content, re.DOTALL)
    if not m:
        raise ValueError("PageList not found")
    return [int(x.strip()) for x in m.group(1).replace("\n", "").split(",") if x.strip()]


def parse_surah_list(content: str) -> list[tuple]:
    """Extract SurahList: [startAyahId, ayahCount, surahOrder, rukuCount, name, isMeccan]"""
    idx = content.find("SurahList")
    if idx == -1:
        raise ValueError("SurahList not found")
    chunk = content[idx:]
    # Find the opening bracket
    start = chunk.index("[")
    # Extract all tuple entries
    entries = re.findall(
        r"\[(-?\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*\"([^\"]*)\",\s*(true|false)\]",
        chunk[start:start + 30000]
    )
    return entries  # entries[0] is the placeholder [-1,...], entries[1] is surah 1


def ayah_id_to_page(ayah_id: int, page_list: list[int]) -> int:
    """
    Given a global ayah ID and the page boundary list,
    return the 1-based page number.
    page_list[0] = 0 (placeholder)
    page_list[1] = first ayah ID on page 1
    page_list[n] = first ayah ID on page n
    """
    # page_list[1..604] contains the start ayah IDs
    # We want the largest index i such that page_list[i] <= ayah_id
    # Use bisect_right to find insertion point, then subtract 1
    # Ignore index 0 (placeholder), work with [1:]
    pages = page_list[1:]  # pages[0] = start of page 1, pages[i] = start of page i+1
    pos = bisect.bisect_right(pages, ayah_id) - 1
    return max(1, pos + 1)  # 1-based page number


def build_metadata(riwayah: str, page_list: list[int], surah_list: list[tuple]) -> dict:
    """Build the output metadata dict for a riwayah."""
    # surah_list[0] is placeholder, surah_list[1..114] are the surahs
    # Fields: [startAyahId, ayahCount, surahOrder, rukuCount, name, isMeccan]
    surahs_out = []
    for i in range(1, 115):  # surahs 1..114
        entry = surah_list[i]
        start_ayah_id = int(entry[0])
        ayah_count = int(entry[1])
        start_page = ayah_id_to_page(start_ayah_id, page_list)
        surahs_out.append({
            "number": i,
            "ayahCount": ayah_count,
            "startPage": start_page,
        })

    total_ayahs = sum(s["ayahCount"] for s in surahs_out)
    # Total pages = page_list entries after index 0, minus sentinel
    # page_list is 606 entries: [0, page1start, ..., page604start, sentinel]
    total_pages = len(page_list) - 2  # subtract placeholder and sentinel

    return {
        "riwayah": riwayah,
        "totalPages": total_pages,
        "totalAyahs": total_ayahs,
        "surahs": surahs_out,
    }


def main():
    dry_run = "--dry-run" in sys.argv

    if not dry_run:
        os.makedirs(OUTPUT_DIR, exist_ok=True)

    for riwayah, filename in RIWAYAT.items():
        print(f"\nProcessing {riwayah} ({filename})...")
        try:
            content = fetch_ts(filename)
            page_list = parse_page_list(content)
            surah_list = parse_surah_list(content)

            if len(surah_list) < 115:
                print(f"  ERROR: Only {len(surah_list)} surah entries found, expected 115+")
                continue

            meta = build_metadata(riwayah, page_list, surah_list)

            print(f"  -> totalPages={meta['totalPages']}, totalAyahs={meta['totalAyahs']}")
            print(f"     Surah 1: page {meta['surahs'][0]['startPage']}, {meta['surahs'][0]['ayahCount']} ayahs")
            print(f"     Surah 2: page {meta['surahs'][1]['startPage']}, {meta['surahs'][1]['ayahCount']} ayahs")
            print(f"     Surah 18: page {meta['surahs'][17]['startPage']}")
            print(f"     Surah 114: page {meta['surahs'][113]['startPage']}")

            if not dry_run:
                out_path = os.path.join(OUTPUT_DIR, f"riwayah_metadata_{riwayah}.json")
                with open(out_path, "w", encoding="utf-8") as f:
                    json.dump(meta, f, ensure_ascii=False, indent=2)
                size_kb = os.path.getsize(out_path) / 1024
                print(f"  Written: {out_path} ({size_kb:.1f} KB)")

        except Exception as e:
            import traceback
            traceback.print_exc()
            print(f"  ERROR for {riwayah}: {e}", file=sys.stderr)

    print("\nDone.")


if __name__ == "__main__":
    main()
