#!/usr/bin/env python3
"""
Reads all *_crop.json files from a directory and prints Swift PDFSource definitions.

Usage:
    # After running pdf_crop_tool.py on each PDF:
    python3 generate_pdf_sources.py Tools/crops/

    # Output is Swift code you can paste into MushafPDFManager.swift
"""

import json
import glob
import sys
import os


def crop_swift(name, crop):
    t, b, l, r = crop["top"], crop["bottom"], crop["leading"], crop["trailing"]
    if t == 0 and b == 0 and l == 0 and r == 0:
        return f"{name}: CropInsets()"
    parts = []
    if t > 0: parts.append(f"top: {t:.3f}")
    if b > 0: parts.append(f"bottom: {b:.3f}")
    if l > 0: parts.append(f"leading: {l:.3f}")
    if r > 0: parts.append(f"trailing: {r:.3f}")
    return f"{name}: CropInsets({', '.join(parts)})"


def main():
    crop_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    files = sorted(glob.glob(os.path.join(crop_dir, "*_crop.json")))

    if not files:
        print(f"No *_crop.json files found in {crop_dir}")
        sys.exit(1)

    for path in files:
        with open(path) as f:
            data = json.load(f)

        var_name = data["filename"].replace("mushaf_", "").replace(".pdf", "")
        print(f'let {var_name} = PDFSource(')
        print(f'    filename: "{data["filename"]}",')
        print(f'    url: URL(string: base + "...")!,  // TODO: fill in URL')
        print(f'    pageOffset: {data["pageOffset"]},')
        print(f'    {crop_swift("cropOpening", data["cropOpening"])},')
        print(f'    {crop_swift("cropRight", data["cropRight"])},')
        print(f'    {crop_swift("cropLeft", data["cropLeft"])}')
        print(f')')
        print()


if __name__ == "__main__":
    main()
