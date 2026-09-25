#!/usr/bin/env python3
"""
Generate the page- and juz-boundary fixtures used by the iOS parser test.

This script reimplements the EXACT logic from MetadataParser.kt (Android) in
Python, parses the SAME quran_metadata.xml that ships in both platforms, and
writes two JSON fixtures:

    WarattilTests/Fixtures/page_boundaries.json   (604 entries)
    WarattilTests/Fixtures/juz_boundaries.json    (30 entries)

The iOS parser test loads these fixtures and asserts that
MetadataParser.getPageBoundaries(n) / getJuzBoundaries(n) on iOS produce
identical (startKey, endKey) pairs for every n. That is Phase 2's definition
of done per BLUEPRINT.

This script is deterministic — rerunning it on an unchanged XML produces
byte-identical JSON. Run from the repo root:

    python3 ios/Tools/generate_boundary_fixture.py
"""

import json
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

REPO_ROOT = Path(__file__).resolve().parents[2]
XML_PATH = REPO_ROOT / "ios" / "Warattil" / "Resources" / "quran_metadata.xml"
OUT_DIR = REPO_ROOT / "ios" / "WarattilTests" / "Fixtures"


def parse_metadata(xml_path: Path):
    """Parse the XML into three lists mirroring the Android data classes."""
    tree = ET.parse(xml_path)
    root = tree.getroot()

    suras, pages, juzs = [], [], []

    for el in root.iter():
        if el.tag == "sura":
            suras.append({
                "index": int(el.attrib["index"]),
                "name":      el.attrib["name"],
                "ayas":  int(el.attrib["ayas"]),
                "start": int(el.attrib["start"]),
            })
        elif el.tag == "page":
            pages.append({
                "index": int(el.attrib["index"]),
                "sura":  int(el.attrib["sura"]),
                "aya":   int(el.attrib["aya"]),
            })
        elif el.tag == "juz":
            juzs.append({
                "index": int(el.attrib["index"]),
                "sura":  int(el.attrib["sura"]),
                "aya":   int(el.attrib["aya"]),
            })

    return suras, pages, juzs


def boundaries(items, suras, last_end):
    """Reproduce the Kotlin getPageBoundaries / getJuzBoundaries algorithm.

    `items` is the pages or juzs list (already sorted by index in the XML).
    `suras` provides the previous-surah-last-ayah fallback.
    `last_end` is the absolute end for the final item (114*10000 + 6).
    """
    by_index = {it["index"]: it for it in items}
    sura_by_index = {s["index"]: s for s in suras}

    out = []
    for it in items:
        idx = it["index"]
        start_key = it["sura"] * 10000 + it["aya"]

        nxt = by_index.get(idx + 1)
        if nxt is not None:
            if nxt["aya"] > 1:
                end_key = nxt["sura"] * 10000 + (nxt["aya"] - 1)
            else:
                prev_sura_idx = nxt["sura"] - 1
                prev_sura = sura_by_index.get(prev_sura_idx)
                if prev_sura is not None:
                    end_key = prev_sura_idx * 10000 + prev_sura["ayas"]
                else:
                    end_key = start_key  # Kotlin fallback
        else:
            end_key = last_end

        out.append({
            "index":    idx,
            "startSura": it["sura"],
            "startAya":  it["aya"],
            "startKey": start_key,
            "endKey":   end_key,
        })
    return out


def main() -> int:
    if not XML_PATH.exists():
        print(f"ERROR: XML not found at {XML_PATH}", file=sys.stderr)
        return 1

    suras, pages, juzs = parse_metadata(XML_PATH)

    print(f"Parsed: {len(suras)} suras, {len(pages)} pages, {len(juzs)} juz")

    # Sanity — BLUEPRINT invariants.
    assert len(suras) == 114, f"expected 114 suras, got {len(suras)}"
    assert len(pages) == 604, f"expected 604 pages, got {len(pages)}"
    assert len(juzs)  == 30,  f"expected 30 juz,    got {len(juzs)}"

    last_end = 114 * 10000 + 6

    page_bounds = boundaries(pages, suras, last_end)
    juz_bounds  = boundaries(juzs,  suras, last_end)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    page_path = OUT_DIR / "page_boundaries.json"
    juz_path  = OUT_DIR / "juz_boundaries.json"

    # Stable, diffable formatting.
    with page_path.open("w", encoding="utf-8") as f:
        json.dump(page_bounds, f, ensure_ascii=False, indent=2)
        f.write("\n")

    with juz_path.open("w", encoding="utf-8") as f:
        json.dump(juz_bounds,  f, ensure_ascii=False, indent=2)
        f.write("\n")

    # Also emit a tiny smoke sample the human can eyeball:
    for p in (1, 2, 3, 604):
        b = next(x for x in page_bounds if x["index"] == p)
        print(f"  page {p:>3}  start={b['startSura']}:{b['startAya']}  "
              f"startKey={b['startKey']}  endKey={b['endKey']}")

    print(f"\nWrote {page_path.relative_to(REPO_ROOT)}")
    print(f"Wrote {juz_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
