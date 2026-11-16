#!/usr/bin/env python3
"""Mutation testing: break one security check at a time and require the test suite to notice.

Two kinds of mutants:
  - automatic: every `if (...) revert ...;` guard under src/ is disabled in turn (for a guard
    written `a || b`, each alternative is dropped in turn), and every unconditional
    `revert ...;` is removed in turn;
  - listed: the changes written in tools/mutations.json (a state update dropped, a field left
    out of a signed digest, a comparison weakened...).

A mutant counts as caught only when forge reports a failing test. A mutant that the suite does
not catch makes this script fail, unless it is listed with a reason in
tools/mutations-accepted.json (a change that cannot alter behaviour; entries are named without
their line number). So does a mutant that does not compile, or a run that ends any other way.

What it does not do: it does not run the symbolic proofs, it does not mutate assembly or
checks written as `return`, and the listed changes are chosen by hand. It shows that a removed
check is noticed, not that no check is missing.

    python3 tools/mutate.py              run everything
    python3 tools/mutate.py --list       print the mutants, run nothing
    python3 tools/mutate.py --only Loan  only mutants whose file or name contains "Loan"

The repository itself is never modified: mutants are built in temporary copies.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP = {"IAgentRegistry.sol", "IERC721AgentOnly.sol"}


def strip_comments(text):
    """Blanks out comments, keeping every offset, so that guards in comments are not mutated."""

    def blank(m):
        return re.sub(r"[^\n]", " ", m.group(0))

    return re.sub(r"//[^\n]*|/\*.*?\*/", blank, text, flags=re.S)


def unnumbered(name):
    """`File.sol:12 guard...` -> `File.sol guard...`: accepted mutants are named without a line."""
    return re.sub(r"^(\S+):\d+ ", r"\1 ", name)


def line_of(text, pos):
    return text.count("\n", 0, pos) + 1


def alternatives(code, start, end):
    """Splits a condition on its top-level `||`. Returns the (start, end) of each alternative."""
    parts, depth, begin, i = [], 0, start, start
    while i < end:
        depth += {"(": 1, ")": -1}.get(code[i], 0)
        if depth == 0 and code.startswith("||", i):
            parts.append((begin, i))
            begin = i + 2
        i += 1
    return parts + [(begin, end)]


def automatic(path):
    """Yields (name, mutated source) for each guard of one file."""
    text = path.read_text()
    code = strip_comments(text)
    guarded = set()
    for m in re.finditer(r"\bif \(", code):
        depth, i = 1, m.end()
        while depth:
            depth += {"(": 1, ")": -1}.get(code[i], 0)
            i += 1
        after = re.match(r"\s*\{?\s*revert\b[^;]*;", code[i:])
        if not after:
            continue
        guarded.add(i + after.group(0).index("revert"))
        where = f"{path.name}:{line_of(text, m.start())}"
        parts = alternatives(code, m.end(), i - 1)
        if len(parts) == 1:
            cond = " ".join(text[m.end() : i - 1].split())
            mutated = text[: m.end()] + "false && (" + text[m.end() : i - 1] + ")" + text[i - 1 :]
            yield f"{where} guard disabled: {cond}", mutated
        for start, end in parts if len(parts) > 1 else []:  # `a || b`: drop each alternative in turn
            dropped = " ".join(text[start:end].split())
            yield f"{where} guard no longer fires on: {dropped}", text[:start] + "false" + text[end:]
    for m in re.finditer(r"\brevert\s+\w[^;]*;", code):  # custom errors only, not assembly
        if m.start() in guarded:
            continue
        what = " ".join(text[m.start() : m.end()].split())
        yield f"{path.name}:{line_of(text, m.start())} removed: {what}", text[: m.start()] + text[m.end() :]


def collect():
    mutants = []
    for path in sorted((ROOT / "src").rglob("*.sol")):
        if path.name in SKIP:
            continue
        rel = str(path.relative_to(ROOT))
        for name, source in automatic(path):
            mutants.append((rel, name, source))
    for entry in json.loads((ROOT / "tools" / "mutations.json").read_text()):
        text = (ROOT / entry["file"]).read_text()
        if text.count(entry["find"]) != 1:
            sys.exit(f"mutations.json: '{entry['name']}' must match exactly once in {entry['file']}")
        name = f"{Path(entry['file']).name} {entry['name']}"
        mutants.append((entry["file"], name, text.replace(entry["find"], entry["replace"])))
    return mutants


def workdir():
    tmp = Path(tempfile.mkdtemp(prefix="mutate-"))
    for item in ("src", "test", "script"):
        shutil.copytree(ROOT / item, tmp / item)
    shutil.copy(ROOT / "foundry.toml", tmp)
    for item in ("lib", "node_modules"):
        os.symlink(ROOT / item, tmp / item)
    return tmp


def run(tmp, mutants, forge_args):
    env = dict(os.environ, FOUNDRY_FUZZ_RUNS="64", FOUNDRY_INVARIANT_RUNS="16")
    results = []
    for rel, name, source in mutants:
        original = (tmp / rel).read_text()
        (tmp / rel).write_text(source)
        try:
            proc = subprocess.run(
                ["forge", "test", "--fail-fast", *forge_args], cwd=tmp, env=env, capture_output=True, text=True,
                timeout=900,
            )
            out, code = proc.stdout + proc.stderr, proc.returncode
        except subprocess.TimeoutExpired:
            out, code = "", None
        (tmp / rel).write_text(original)
        if "Compiler run failed" in out or "Compilation failed" in out:
            verdict = "invalid"
        elif code == 0:
            verdict = "missed"
        elif code is not None and ("[FAIL" in out or "Suite result: FAILED" in out):
            verdict = "caught"
        else:  # forge crashed, timed out or failed for another reason: not a proof of anything
            verdict = "error"
        print(f"{verdict.upper():8}{name}", flush=True)
        results.append((name, verdict))
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--only", default="")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("forge_args", nargs="*", help="extra arguments for forge test, after --")
    args = parser.parse_args()

    mutants = [m for m in collect() if args.only in m[1]]
    if args.list:
        for _, name, _ in mutants:
            print(name)
        print(f"{len(mutants)} mutants")
        return

    # The intact suite must pass first, or every mutant would look caught.
    base = workdir()
    intact = subprocess.run(["forge", "test", *args.forge_args], cwd=base, capture_output=True, text=True)
    if intact.returncode != 0:
        sys.exit("the intact test suite fails:\n" + intact.stdout[-2000:] + intact.stderr[-2000:])

    dirs = [base] + [workdir() for _ in range(args.jobs - 1)]
    for d in dirs[1:]:  # start from the compiled state
        for item in ("out", "cache"):
            shutil.copytree(base / item, d / item)
    shares = [mutants[i :: args.jobs] for i in range(args.jobs)]
    with ThreadPoolExecutor(args.jobs) as pool:
        results = sum(pool.map(lambda p: run(p[0], p[1], args.forge_args), zip(dirs, shares)), [])
    for d in dirs:
        shutil.rmtree(d, ignore_errors=True)

    accepted = json.loads((ROOT / "tools" / "mutations-accepted.json").read_text())
    not_caught = {unnumbered(n) for n, v in results if v == "missed"}
    missed = [n for n, v in results if v == "missed" and unnumbered(n) not in accepted]
    invalid = [n for n, v in results if v == "invalid"]
    errors = [n for n, v in results if v == "error"]
    stale = [n for n in accepted if not args.only and n not in not_caught]
    caught = sum(v == "caught" for _, v in results)
    print(f"\n{len(results)} mutants: {caught} caught, {len(not_caught)} not caught "
          f"({len(missed)} unexplained), {len(invalid)} do not compile, {len(errors)} could not be judged")
    for title, names in (("NOT CAUGHT", missed), ("DOES NOT COMPILE", invalid), ("COULD NOT BE JUDGED", errors),
                         ("ACCEPTED BUT NO LONGER MISSED", stale)):
        for n in names:
            print(f"{title}: {n}")
    sys.exit(1 if missed or invalid or errors or stale else 0)


if __name__ == "__main__":
    main()
