#!/usr/bin/env python3
"""Watches the Intel data that Automata's DCAP verifier needs on Base Sepolia.

    python3 tools/collateral.py                    the archived quotes of our machines
    python3 tools/collateral.py --warn-days 3      fails if one would be refused within 3 days

For each quote, asks the real DCAP verifier, through eth_call with a simulated block time,
until which day it still accepts the quote, and at which platform level. Then reads Intel's
list of TCB recoveries stored on chain and tries each recent one: a deployment can only demand
an evaluation whose data is on chain. Nothing is sent, nothing is signed; Python 3 only.

Why: the verifier refuses every quote once the Intel data on chain expires (about a month after
it was issued) until someone publishes newer data, and Intel publishes TCB recoveries that the
on-chain data may not include yet. Both stop enrollments and key rotations. The procedure that
answers each case is docs/platform-updates.md.
"""

import argparse
import glob
import json
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RPC = "https://sepolia.base.org"
DCAP = "0xaDdeC7e85c2182202b66E331f2a4A0bBB2cEEa1F"  # Automata DCAP Attestation, Base Sepolia
TCB_EVAL_DAO = "0xcF614258C68730D8cB9713AcAe425875D1FDb370"  # Automata TcbEvalDao, Base Sepolia
QUOTES = ["test/experimental/phala/quote*.hex"]
DAY = 86400
HORIZON = 60  # days searched ahead


def rpc(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    request = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json", "User-Agent": "curl/8"})
    return json.load(urllib.request.urlopen(request, timeout=90))


def word(n):
    return n.to_bytes(32, "big").hex()


def encode_bytes(selector, data, *extra):
    """Calldata for f(bytes) or f(bytes,uint32): head, then the bytes padded to 32."""
    head = word(32 * (1 + len(extra))) + "".join(word(x) for x in extra)
    padded = data + b"\0" * (-len(data) % 32)
    return "0x" + selector + head + word(len(data)) + padded.hex()


VERIFY = "38d8480a"  # verifyAndAttestOnChain(bytes): Intel's "standard" evaluation
VERIFY_AT = "1beaf6d8"  # verifyAndAttestOnChain(bytes,uint32): a given evaluation


def verify(url, quote, at, evaluation=None):
    """(accepted, platform level or reason) for the quote at a simulated time."""
    data = encode_bytes(VERIFY, quote) if evaluation is None else encode_bytes(VERIFY_AT, quote, evaluation)
    call = {"to": DCAP, "data": data, "gas": hex(30_000_000)}
    answer = rpc(url, "eth_call", [call, "latest", None, {"time": hex(at)}])
    if "error" in answer:
        return False, "reverted " + str(answer["error"].get("data", ""))[:10]
    out = bytes.fromhex(answer["result"][2:])
    ok = int.from_bytes(out[:32], "big") == 1
    payload = out[64 + 32 : 64 + 32 + int.from_bytes(out[64:96], "big")]
    return (ok, payload[4]) if ok else (ok, payload.decode(errors="replace"))


def last_day(url, quote, now):
    """Last whole day, from now, on which the quote is still accepted (-1: refused now)."""
    if not verify(url, quote, now)[0]:
        return -1
    lo, hi = 0, HORIZON
    if verify(url, quote, now + hi * DAY)[0]:
        return hi
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if verify(url, quote, now + mid * DAY)[0]:
            lo = mid
        else:
            hi = mid
    return lo


def recoveries(url):
    """Intel's TCB recoveries for TDX, as stored on chain: (issued, expires, [(number, date)])."""
    answer = rpc(url, "eth_call", [{"to": TCB_EVAL_DAO, "data": "0xa92bf07d" + word(1)}, "latest"])
    raw = bytes.fromhex(answer["result"][2:])
    start = int.from_bytes(raw[32:64], "big") + int.from_bytes(raw[0:32], "big")
    text = raw[start + 32 : start + 32 + int.from_bytes(raw[start : start + 32], "big")]
    data = json.loads(text)
    numbers = [(e["tcbEvaluationDataNumber"], e["tcbRecoveryEventDate"][:10]) for e in data["tcbEvalNumbers"]]
    return data["issueDate"], data["nextUpdate"], numbers


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--rpc", default=RPC)
    parser.add_argument("--warn-days", type=int, default=3)
    args = parser.parse_args()

    now = int(time.time())
    quotes = {}
    for pattern in QUOTES:
        for path in sorted(ROOT.glob(pattern)):
            quotes.setdefault(bytes.fromhex(path.read_text().strip()[2:]), path.relative_to(ROOT))
    problems = []

    issued, expires, numbers = recoveries(args.rpc)
    print(f"Intel's TCB evaluation list on chain: issued {issued}, expires {expires}")
    print("  latest recoveries: " + ", ".join(f"{n} ({d})" for n, d in numbers[:4]))

    for quote, path in quotes.items():
        ok, level = verify(args.rpc, quote, now)
        days = last_day(args.rpc, quote, now)
        tried = []
        for number, _ in numbers[:4]:
            accepted, result = verify(args.rpc, quote, now, number)
            tried.append(f"{number}: {'level ' + str(result) if accepted else 'cannot be checked'}")
        print(f"{path}: {'accepted, platform level ' + str(level) if ok else 'refused: ' + str(level)}; "
              f"still accepted in {days} day(s)" + (f" or more" if days == HORIZON else ""))
        print("  by evaluation: " + "; ".join(tried))
        if days < args.warn_days:
            problems.append(f"{path}: refused within {args.warn_days} day(s) (last accepted day: {days})")

    for problem in problems:
        print("PROBLEM: " + problem)
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
