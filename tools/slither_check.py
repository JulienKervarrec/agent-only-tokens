#!/usr/bin/env python3
"""Compares a Slither report with the list of accepted findings.

    slither . --filter-paths "node_modules|lib" --json slither.json || true
    python3 tools/slither_check.py slither.json

Each finding is named by its detector and the place it points at (contract, function,
variable), not by line numbers, so that the list survives edits. A finding that is not in
tools/slither-accepted.json makes the check fail; so does an accepted finding that Slither
no longer reports, so that the list stays true.
"""

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def place(element):
    names = [element.get("name", "")]
    parent = element.get("type_specific_fields", {}).get("parent")
    while parent:
        names.append(parent.get("name", ""))
        parent = parent.get("type_specific_fields", {}).get("parent")
    if element["type"] == "node":  # a statement: name the function it is in
        names = names[1:]
    return ".".join(reversed([n for n in names if n]))


def key(finding):
    return f"{finding['check']}: {place(finding['elements'][0]) if finding['elements'] else '-'}"


def main():
    report = json.loads(Path(sys.argv[1]).read_text())
    if not report.get("success"):
        sys.exit(f"Slither did not run: {report.get('error')}")
    found = Counter(key(f) for f in report["results"].get("detectors", []))
    accepted = json.loads((ROOT / "tools" / "slither-accepted.json").read_text())
    if "--list" in sys.argv:
        for name in sorted(found):
            print(name)
        return
    new = sorted(k for k in found if k not in accepted)
    gone = sorted(k for k in accepted if k not in found)
    for name in new:
        print(f"NEW: {name}")
    for name in gone:
        print(f"NO LONGER REPORTED: {name}")
    print(f"{sum(found.values())} findings, {len(found)} distinct, {len(accepted)} accepted, "
          f"{len(new)} new, {len(gone)} no longer reported")
    sys.exit(1 if new or gone else 0)


if __name__ == "__main__":
    main()
