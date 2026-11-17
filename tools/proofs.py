#!/usr/bin/env python3
"""Checks that each symbolic proof of the registry fails when the rule it states is broken.

A proof that still passes on broken code proves nothing. tools/broken-registries.json lists
changes to src/AttestedAgentRegistry.sol, each with the proofs that must then fail. This
script first runs the proofs of RegistryProps on the registry as it is (all must pass), then
applies each change to a copy of the repository and runs them again: exactly the listed proofs
must fail, and every other one must pass.

    python3 tools/proofs.py            # everything, a few minutes
    python3 tools/proofs.py --list     # the changes and the proofs they must break

Needs forge and halmos (pip install halmos==0.3.3).
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGET = "src/AttestedAgentRegistry.sol"


def proofs(tmp):
    """Runs the registry proofs in `tmp`; returns the names that passed and those that did not."""
    out = subprocess.run(["halmos", "--match-contract", "RegistryProps"], cwd=tmp, capture_output=True, text=True)
    text = re.sub(r"\x1b\[[0-9;]*m", "", out.stdout + out.stderr)
    passed = set(re.findall(r"\[PASS\] (check_\w+)", text))
    failed = set(re.findall(r"\[(?:FAIL|TIMEOUT|ERROR)\] (check_\w+)", text))
    return passed, failed, text


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--list", action="store_true", help="list the changes and stop")
    args = parser.parse_args()
    broken = json.loads((ROOT / "tools" / "broken-registries.json").read_text())
    original = (ROOT / TARGET).read_text()
    for entry in broken:
        if original.count(entry["find"]) != 1:
            sys.exit(f"broken-registries.json: '{entry['name']}' must match exactly once in {TARGET}")
    if args.list:
        for entry in broken:
            print(f"{entry['name']}: {', '.join(entry['fails'])}")
        print(f"{len(broken)} broken registries")
        return

    tmp = Path(tempfile.mkdtemp(prefix="proofs-"))
    for item in ("src", "test", "script"):
        shutil.copytree(ROOT / item, tmp / item)
    shutil.copy(ROOT / "foundry.toml", tmp)
    for item in ("lib", "node_modules"):
        os.symlink(ROOT / item, tmp / item)

    passed, failed, text = proofs(tmp)
    if failed or not passed:
        print(text[-2000:])
        sys.exit("the proofs do not pass on the registry as it is")
    every = passed
    print(f"unchanged registry: {len(every)} proofs pass")
    problems = 0
    for entry in broken:
        (tmp / TARGET).write_text(original.replace(entry["find"], entry["replace"]))
        passed, failed, _ = proofs(tmp)
        expected = set(entry["fails"])
        good = failed == expected and passed == every - expected
        problems += not good
        print(f"{'OK ' if good else 'BAD'} {entry['name']}: failed {sorted(failed) or 'nothing'}", flush=True)
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"{len(broken)} broken registries, {problems} problem(s)")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
