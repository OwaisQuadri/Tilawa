#!/usr/bin/env python3
"""
riwayah_compat_editor.py — Interactive CLI for editing riwayah compatibility groups

USAGE
    python3 Scripts/riwayah_compat_editor.py [OPTIONS] [SURAH:AYAH]

ARGUMENTS
    SURAH:AYAH   Jump directly to that position, e.g. 2:255
                 (default: first unreviewed ayah)

OPTIONS
    --populate       Fill all 6236 ayahs with 20-singleton (unreviewed) entries,
                     preserving any already-reviewed entries
    --reset-all      Reset every entry in the file to 20-singleton (unreviewed).
                     Asks for confirmation before writing. Cannot be undone.
    --deploy         Copy Scripts/riwayah_compat_draft.json → Tilawa/Resources/riwayah_compatibility.json
    --file PATH      Use a specific JSON file instead of the default draft
                     (default: Scripts/riwayah_compat_draft.json)
    -h, --help       Show this help

WORKFLOW
    1. Run builder first: python3 Scripts/riwayah_compat_builder.py
    2. Edit draft:        python3 Scripts/riwayah_compat_editor.py
    3. Deploy to app:     python3 Scripts/riwayah_compat_editor.py --deploy

FILES
    Default draft: Scripts/riwayah_compat_draft.json  (app untouched until deploy)
    App file:      Tilawa/Resources/riwayah_compatibility.json

EDITING CONVENTIONS
    20 groups of 1    UNREVIEWED — each riwayah only matches itself (strict)
    1 group of 20     ALL-SAME   — all 20 riwayaat are compatible at this ayah
    2–19 groups       SPLIT      — partial compatibility (some match, some don't)

PROGRESS
    Counts ayahs that are NOT the default 20-singleton pattern / 6236 total.
    An ayah set by the builder (8 riwayahs grouped, 12 singletons) counts as reviewed.
"""

import json
import os
import shutil
import sys
import readline  # noqa: F401  — enables arrow keys / history in input()

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR    = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT  = os.path.dirname(SCRIPT_DIR)
METADATA_JSON = os.path.join(PROJECT_ROOT, "Tilawa/Resources/QuranData/quran-metadata.json")
DRAFT_JSON    = os.path.join(SCRIPT_DIR, "riwayah_compat_draft.json")
APP_JSON      = os.path.join(PROJECT_ROOT, "Tilawa/Resources/riwayah_compatibility.json")

# Defaults to draft; use --file PATH to override
_file_flag = next((sys.argv[i+1] for i, a in enumerate(sys.argv) if a == "--file" and i+1 < len(sys.argv)), None)
COMPAT_JSON = os.path.abspath(_file_flag) if _file_flag else DRAFT_JSON

# ── The 20 canonical riwayaat ─────────────────────────────────────────────────
RIWAYAAT = [
    "hafs", "shuabah", "warsh", "qaloon", "bazzi", "qunbul",
    "doori_abu_amr", "soosi", "hisham", "ibn_dhakwan",
    "khalaf_an_hamza", "khallad", "abul_harith", "doori_al_kisai",
    "ibn_wardan", "ibn_jammaz", "ruways", "rawh", "ishaq", "idris",
]
RIWAYAH_SET     = set(RIWAYAAT)
SINGLETON_GROUPS = [[r] for r in RIWAYAAT]   # 20 × 1 = unreviewed default

# ── ANSI ──────────────────────────────────────────────────────────────────────
BOLD   = "\033[1m"
DIM    = "\033[2m"
CYAN   = "\033[36m"
GREEN  = "\033[32m"
YELLOW = "\033[33m"
RED    = "\033[31m"
RESET  = "\033[0m"

def bold(s):   return f"{BOLD}{s}{RESET}"
def dim(s):    return f"{DIM}{s}{RESET}"
def cyan(s):   return f"{CYAN}{s}{RESET}"
def green(s):  return f"{GREEN}{s}{RESET}"
def yellow(s): return f"{YELLOW}{s}{RESET}"
def red(s):    return f"{RED}{s}{RESET}"


# ── Reviewed / progress ───────────────────────────────────────────────────────

def is_reviewed(groups):
    """True if entry has been assigned (not the default 20-singleton pattern)."""
    if not groups:
        return False
    return not (len(groups) == 20 and all(len(g) == 1 for g in groups))


def compute_progress(table, total_ayahs):
    reviewed = sum(1 for g in table.values() if is_reviewed(g))
    return reviewed, total_ayahs


def first_unreviewed(table, surahs):
    """Return (surah, ayah) of the first unreviewed ayah, or None if all done."""
    for surah in range(1, 115):
        for ayah in range(1, surahs[surah]["ayahCount"] + 1):
            key = (surah, ayah)
            if key not in table or not is_reviewed(table[key]):
                return surah, ayah
    return None


# ── Load / save ───────────────────────────────────────────────────────────────

def load_metadata():
    with open(METADATA_JSON) as f:
        data = json.load(f)
    surahs = {}
    cumulative = {}
    c = 0
    for s in data["surahs"]:
        n = s["number"]
        surahs[n] = {"name": s["englishName"], "ayahCount": s["ayahCount"]}
        cumulative[n] = c
        c += s["ayahCount"]
    total = c
    return surahs, cumulative, total


def load_compat():
    with open(COMPAT_JSON) as f:
        entries = json.load(f)
    return {(e["surah"], e["ayah"]): e["groups"] for e in entries}


def save_compat(table):
    entries = [
        {"surah": s, "ayah": a, "groups": table[(s, a)]}
        for (s, a) in sorted(table.keys())
    ]
    with open(COMPAT_JSON, "w") as f:
        json.dump(entries, f, separators=(",", ":"), ensure_ascii=False)
    print(green(f"  Saved {len(entries)} entries → {os.path.relpath(COMPAT_JSON)}"))


def populate_table(table, surahs):
    """Insert 20-singleton entries for every ayah not already in the table."""
    added = 0
    for surah in range(1, 115):
        for ayah in range(1, surahs[surah]["ayahCount"] + 1):
            key = (surah, ayah)
            if key not in table:
                table[key] = [list(g) for g in SINGLETON_GROUPS]
                added += 1
    return added


# ── Display ───────────────────────────────────────────────────────────────────

def groups_summary(groups):
    if not groups:
        return f"  {yellow('Not in file')}  {dim('(strict mode)')}"
    if len(groups) == 20 and all(len(g) == 1 for g in groups):
        return f"  {yellow('Unreviewed')}  {dim('(20 × 1 — all strict)')}"
    if len(groups) == 1 and set(groups[0]) == RIWAYAH_SET:
        return f"  {green('All same')}  {dim('(1 group of 20 — all compatible)')}"
    lines = []
    for i, g in enumerate(groups, 1):
        lines.append(f"  {bold(f'Group {i}:')} {', '.join(g)}  {dim(f'({len(g)})')}")
    return "\n".join(lines)


def riwayaat_grid():
    cols, rows = 4, 5   # 20 riwayaat = 4 cols × 5 rows
    lines = []
    for r in range(rows):
        parts = []
        for c in range(cols):
            idx = r + c * rows + 1
            if idx <= len(RIWAYAAT):
                label = f"{cyan(str(idx).rjust(2))}) {RIWAYAAT[idx - 1]}"
                parts.append(f"{label:<32}")
        lines.append("  " + "".join(parts))
    return "\n".join(lines)


def progress_bar(reviewed, total, width=28):
    pct = reviewed / total if total else 0
    filled = int(width * pct)
    bar = "█" * filled + "░" * (width - filled)
    return f"{green(bar)} {pct * 100:.1f}%  {dim(f'({reviewed}/{total})')}"


def print_header(surah, ayah, surahs, cumulative, table, total_ayahs):
    name     = surahs[surah]["name"]
    abs_ayah = cumulative[surah] + ayah
    reviewed, total = compute_progress(table, total_ayahs)
    key = (surah, ayah)
    print()
    print("━" * 60)
    print(f"  {bold(f'{name} {surah}:{ayah}')}  {dim(f'(#{abs_ayah} of {total})')}")
    print(f"  {progress_bar(reviewed, total)}")
    print("━" * 60)
    print(groups_summary(table.get(key)))


def print_commands():
    cmds = [
        ("[a]", "all-same"),
        ("[e]", "edit groups"),
        ("[r]", "reset ayah"),
        ("[d]", "delete"),
        ("[n/↵]", "next"),
        ("[p]", "prev"),
        ("[g]", "goto S:A"),
        ("[s]", "save"),
        ("[q]", "quit+save"),
    ]
    print("\n  " + "  ".join(f"{cyan(k)} {v}" for k, v in cmds))


# ── Navigation ────────────────────────────────────────────────────────────────

def next_ayah(surah, ayah, surahs):
    if ayah < surahs[surah]["ayahCount"]:
        return surah, ayah + 1
    if surah < 114:
        return surah + 1, 1
    return surah, ayah


def prev_ayah(surah, ayah, surahs):
    if ayah > 1:
        return surah, ayah - 1
    if surah > 1:
        prev = surah - 1
        return prev, surahs[prev]["ayahCount"]
    return surah, ayah


# ── Group editor ─────────────────────────────────────────────────────────────

def parse_numbers(s):
    nums = []
    for p in s.replace(",", " ").split():
        try:
            n = int(p)
            if 1 <= n <= 20:
                nums.append(n)
            else:
                print(red(f"  {n} is out of range (1–20)"))
                return None
        except ValueError:
            print(red(f"  '{p}' is not a number"))
            return None
    return nums


def edit_groups(surah, ayah, surahs, table):
    name = surahs[surah]["name"]
    print(f"\n  {bold('Edit groups')} for {name} {surah}:{ayah}")
    print(f"  {dim('Select numbers for each group. Enter alone = all remaining → this group.')}\n")
    print(riwayaat_grid())
    print()

    remaining = list(range(1, 21))
    groups    = []

    while remaining:
        gnum = len(groups) + 1
        rem_names = ", ".join(RIWAYAAT[i - 1] for i in remaining)
        print(f"  {cyan(f'Group {gnum}')}  {dim(f'({len(remaining)} left: {rem_names})')}")
        if gnum > 1:
            print(f"  {dim('Enter alone → assign all remaining here')}")

        raw = input("  > ").strip()

        if not raw and gnum == 1:
            print(dim("  Cancelled."))
            return table

        if not raw:
            groups.append([RIWAYAAT[i - 1] for i in remaining])
            remaining = []
            break

        nums = parse_numbers(raw)
        if nums is None:
            continue
        if len(set(nums)) != len(nums):
            print(red("  Duplicate numbers — try again."))
            continue
        bad = [n for n in nums if n not in remaining]
        if bad:
            print(red(f"  Already assigned: {', '.join(RIWAYAAT[n-1] for n in bad)}"))
            continue

        groups.append([RIWAYAAT[i - 1] for i in nums])
        remaining = [i for i in remaining if i not in nums]
        print(f"  → {green(', '.join(groups[-1]))}")
        print()

    if not groups:
        print(dim("  Cancelled."))
        return table

    print()
    print(bold("  Preview:"))
    print(groups_summary(groups))
    if input("\n  Save? [y/n]: ").strip().lower() == "y":
        table[(surah, ayah)] = groups
        print(green("  Saved."))
    else:
        print(dim("  Discarded."))
    return table


# ── Main loop ─────────────────────────────────────────────────────────────────

def parse_ref(s):
    parts = s.split(":")
    if len(parts) != 2:
        return None
    try:
        return int(parts[0]), int(parts[1])
    except ValueError:
        return None


def run(start_surah=None, start_ayah=None):
    surahs, cumulative, total_ayahs = load_metadata()
    table = load_compat()
    dirty = False

    if start_surah is None:
        pos = first_unreviewed(table, surahs)
        if pos:
            surah, ayah = pos
        else:
            print(green("  🎉 All 6236 ayahs reviewed!"))
            surah, ayah = 1, 1
    else:
        surah, ayah = start_surah, start_ayah
        if surah not in surahs:
            print(red(f"Invalid surah {surah}"))
            sys.exit(1)
        if ayah < 1 or ayah > surahs[surah]["ayahCount"]:
            print(red(f"Ayah {ayah} out of range for surah {surah}"))
            sys.exit(1)

    while True:
        print_header(surah, ayah, surahs, cumulative, table, total_ayahs)
        print(f"\n{riwayaat_grid()}")
        print_commands()

        try:
            raw = input(f"\n  {cyan('>')} ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            raw = "q"

        if raw in ("q", "quit"):
            if dirty:
                save_compat(table)
            else:
                print(dim("  No changes."))
            break

        elif raw in ("n", "next", ""):
            surah, ayah = next_ayah(surah, ayah, surahs)

        elif raw in ("p", "prev"):
            surah, ayah = prev_ayah(surah, ayah, surahs)

        elif raw in ("a", "all-same", "all"):
            table[(surah, ayah)] = [list(RIWAYAAT)]
            dirty = True
            print(green("  ✓ all-same"))
            surah, ayah = next_ayah(surah, ayah, surahs)

        elif raw in ("e", "edit"):
            before = {k: v for k, v in table.items()}
            table = edit_groups(surah, ayah, surahs, table)
            if table != before:
                dirty = True

        elif raw in ("r", "reset"):
            table[(surah, ayah)] = [list(g) for g in SINGLETON_GROUPS]
            dirty = True
            print(yellow("  ↺ Reset to unreviewed (20 singletons)."))

        elif raw in ("d", "delete"):
            key = (surah, ayah)
            if key in table:
                del table[key]
                dirty = True
                print(green("  Deleted (entry removed from file)."))
            else:
                print(dim("  Not in file — nothing to delete."))

        elif raw.startswith("g") or ":" in raw:
            ref_str = raw[1:].strip() if raw.startswith("g") else raw
            ref = parse_ref(ref_str)
            if ref is None:
                print(red("  Format: SURAH:AYAH  e.g.  g 2:255  or  2:255"))
            else:
                s, a = ref
                if s not in surahs:
                    print(red(f"  Invalid surah {s}"))
                elif a < 1 or a > surahs[s]["ayahCount"]:
                    print(red(f"  Ayah {a} out of range for surah {s}"))
                else:
                    surah, ayah = s, a

        elif raw in ("s", "save"):
            save_compat(table)
            dirty = False

        elif raw == "?":
            print_commands()

        else:
            print(dim("  Unknown command — '?' for help."))


def main():
    if "-h" in sys.argv or "--help" in sys.argv:
        print(__doc__)
        return

    if len(sys.argv) > 1 and sys.argv[1] == "--deploy":
        if not os.path.exists(DRAFT_JSON):
            print(red("  No draft found. Run the builder first."))
            sys.exit(1)
        shutil.copy2(DRAFT_JSON, APP_JSON)
        print(green(f"  Deployed {os.path.relpath(DRAFT_JSON)} → {os.path.relpath(APP_JSON)}"))
        return

    if len(sys.argv) > 1 and sys.argv[1] == "--reset-all":
        confirm = input(red("  Reset ALL entries to unreviewed? This cannot be undone. [yes/N]: ")).strip()
        if confirm.lower() == "yes":
            table = load_compat()
            for key in table:
                table[key] = [list(g) for g in SINGLETON_GROUPS]
            save_compat(table)
            print(yellow(f"  ↺ Reset {len(table)} entries to unreviewed."))
        else:
            print(dim("  Cancelled."))
        return

    if len(sys.argv) > 1 and sys.argv[1] in ("--populate", "-p"):
        surahs, _, _ = load_metadata()
        table = load_compat()
        added = populate_table(table, surahs)
        if added:
            save_compat(table)
            print(green(f"  Populated {added} unreviewed entries (20 singletons each)."))
        else:
            print(dim("  All 6236 ayahs already in file — nothing added."))
        return

    start_surah = start_ayah = None
    if len(sys.argv) > 1:
        ref = parse_ref(sys.argv[1])
        if ref is None:
            print(red(f"Usage: {sys.argv[0]} [SURAH:AYAH | --populate | --reset-all | --deploy | -h]"))
            sys.exit(1)
        start_surah, start_ayah = ref

    run(start_surah, start_ayah)


if __name__ == "__main__":
    main()
