#!/usr/bin/env python3
"""Keeps the figures quoted in the documentation equal to what the repository contains.

A figure is written in the Markdown files between two invisible markers:

    <!--f:tests-->138<!--/f--> tests

    python3 tools/figures.py            fails if a marked figure differs from the repository
    python3 tools/figures.py --write    rewrites the marked figures
    python3 tools/figures.py --list     prints every figure that can be marked

Figures: number of tests (`forge test --list`), lines per contract, gas per operation
(snapshots/Gas.json, which `forge test --isolate --match-contract GasTest` rewrites),
symbolic proofs, mutants, accepted Slither findings, deployed and verified contracts.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ["README.md", "docs/study.md", "src/experimental/README.md", "examples/enclave-agent/README.md"]
MARK = re.compile(r"<!--f:([\w.]+)-->(.*?)<!--/f-->")


def number(n):
    return f"{n:,}"


def figures(forge_args):
    out = {}
    for path in sorted((ROOT / "src").rglob("*.sol")):
        out[f"lines.{path.stem}"] = number(len(path.read_text().splitlines()))

    listing = subprocess.run(["forge", "test", "--list", "--json", *forge_args], cwd=ROOT, capture_output=True, text=True)
    if listing.returncode != 0:
        sys.exit("forge test --list failed:\n" + listing.stderr[-2000:])
    per_file = {f: sum(len(t) for t in suites.values()) for f, suites in json.loads(listing.stdout.splitlines()[-1]).items()}
    fork = sum(n for f, n in per_file.items() if f.startswith("test/fork/"))
    experimental = sum(n for f, n in per_file.items() if f.startswith("test/experimental/"))
    out["tests"] = number(sum(per_file.values()) - fork)
    out["tests.fork"] = number(fork)
    out["tests.experimental"] = number(experimental)
    for f, n in per_file.items():
        out[f"tests.{Path(f).name.split('.')[0]}"] = number(n)

    for name, gas in json.loads((ROOT / "snapshots" / "Gas.json").read_text()).items():
        out[f"gas.{name[:2]}"] = number(int(gas))

    halmos = "".join(p.read_text() for p in (ROOT / "test" / "halmos").glob("*.sol"))
    out["proofs"] = number(len(re.findall(r"function check_", halmos)))

    mutants = subprocess.run([sys.executable, "tools/mutate.py", "--list"], cwd=ROOT, capture_output=True, text=True, check=True)
    total = int(mutants.stdout.split()[-2])
    listed = len(json.loads((ROOT / "tools" / "mutations.json").read_text()))
    out["mutants"], out["mutants.listed"], out["mutants.automatic"] = number(total), number(listed), number(total - listed)
    out["mutants.accepted"] = number(len(json.loads((ROOT / "tools" / "mutations-accepted.json").read_text())))
    out["slither.accepted"] = number(len(json.loads((ROOT / "tools" / "slither-accepted.json").read_text())))

    deployed = json.loads((ROOT / "deployments" / "base-sepolia.json").read_text())["contracts"]
    verified = [c["sourcify"] for c in deployed if "sourcify" in c]
    out["deployed"] = number(len(deployed))
    out["deployed.clones"] = number(len(deployed) - len(verified))
    out["deployed.verified"] = number(len(verified))
    out["deployed.exact"] = number(verified.count("exact_match"))
    out["deployed.match"] = number(verified.count("match"))
    return out


def main():
    args = sys.argv[1:]
    forge_args = args[args.index("--") + 1 :] if "--" in args else []
    values = figures(forge_args)
    if "--list" in args:
        for name, value in values.items():
            print(f"{name:40}{value}")
        return

    problems, marked = [], 0
    for doc in DOCS:
        path = ROOT / doc
        text = path.read_text()

        def fix(match):
            nonlocal marked
            marked += 1
            name, written = match.group(1), match.group(2)
            if name not in values:
                problems.append(f"{doc}: unknown figure '{name}'")
                return match.group(0)
            if written != values[name]:
                problems.append(f"{doc}: {name} is written {written}, the repository says {values[name]}")
            return f"<!--f:{name}-->{values[name]}<!--/f-->"

        updated = MARK.sub(fix, text)
        if "--write" in args and updated != text:
            path.write_text(updated)

    if "--write" in args:
        problems = [p for p in problems if "unknown figure" in p]
    for problem in problems:
        print(problem)
    print(f"{marked} marked figures, {len(problems)} problem(s)")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
