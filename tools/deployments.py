#!/usr/bin/env python3
"""Checks deployments/base-sepolia.json against the documentation and, optionally, the chain.

    python3 tools/deployments.py                              every address cited in the
                                                              documentation, the scripts and the
                                                              fork tests is in the file
    python3 tools/deployments.py --rpc https://sepolia.base.org
                                                              and the code at each address is
                                                              still the code recorded (needs
                                                              `cast`, from Foundry)
"""

import argparse
import json
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CITED_IN = ["README.md", "docs/study.md", "examples/*/README.md", "examples/*/*/README.md", "examples/x402/*.mjs",
            "script/*.sol", "test/fork/*.sol"]


def rpc(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    request = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json", "User-Agent": "curl/8"})
    answer = json.load(urllib.request.urlopen(request, timeout=30))
    if "error" in answer:
        sys.exit(f"{method}: {answer['error']}")
    return answer["result"]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--rpc")
    args = parser.parse_args()

    book = json.loads((ROOT / "deployments" / "base-sepolia.json").read_text())
    groups = ("contracts", "external", "sessionKeys", "otherChains")
    known = {entry["address"].lower() for group in groups for entry in book[group]}
    problems = []

    for pattern in CITED_IN:
        for path in sorted(ROOT.glob(pattern)):
            for address in set(re.findall(r"0x[0-9a-fA-F]{40}\b", path.read_text())):
                if address.lower() not in known and not address.startswith("0x" + "0" * 30):
                    problems.append(f"{path.relative_to(ROOT)} cites {address}, which is not in the deployments file")

    if args.rpc:
        if int(rpc(args.rpc, "eth_chainId", []), 16) != book["chainId"]:
            sys.exit("the RPC is not on the chain of the deployments file")
        for entry in book["contracts"] + book["external"]:
            code = rpc(args.rpc, "eth_getCode", [entry["address"], "latest"])
            found = subprocess.run(["cast", "keccak", code], capture_output=True, text=True, check=True).stdout.strip()
            if found != entry["codeHash"]:
                problems.append(f"{entry['address']} ({entry['name']}): code hash is {found}, recorded {entry['codeHash']}")
        for entry in book["sessionKeys"]:
            if rpc(args.rpc, "eth_getCode", [entry["address"], "latest"]) != "0x":
                problems.append(f"{entry['address']}: recorded as a key, but holds code")

    for problem in problems:
        print(problem)
    checked = len(book["contracts"]) + len(book["external"])
    print(f"{len(known)} addresses recorded" + (f", {checked} checked on chain" if args.rpc else "") +
          f", {len(problems)} problem(s)")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
