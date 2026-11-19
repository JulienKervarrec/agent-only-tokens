#!/usr/bin/env python3
"""Checks a journal returned by the sixth agent program (GET /journal/quote?nonce=...).

  verify_journal.py ANSWER.json --nonce 0x...            # chain and report data only
  verify_journal.py ANSWER.json --nonce 0x... --rpc URL --dcap ADDRESS --compose-hash HEX
                                                         # plus Intel's check, read-only, on chain

It recomputes the hash chain from the entries, checks that the quote's report data binds that
head, that length and the nonce you chose, and, with --rpc, that Automata's DCAP verifier calls the
quote genuine, that the machine is not in debug mode, that its MRCONFIGID names the program (the
compose hash given), and, if the answer carries the event log, that it replays to RTMR3 with exactly
that one compose hash. What it proves: the measured program, on that
machine, stated this ordered list of entries when it answered. What it does not: that nothing
happened before the program's last start (a restart begins a new journal), or after the quote.
No dependency beyond the Python standard library.
"""
import argparse, hashlib, json, sys, urllib.request

TAG = hashlib.sha256(b"agent-only-tokens.journal.v1").digest()
SELECTOR = "38d8480a"  # verifyAndAttestOnChain(bytes)
OUT_BODY = 11  # DCAP verifier output: version(2) body type(2) tcb(1) platform(6), then the body


def jcs(v):
    # RFC 8785 for the JSON this program writes: strings, integers, booleans, null, objects, lists.
    if isinstance(v, bool) or v is None:
        return json.dumps(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "[" + ",".join(jcs(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ",".join(json.dumps(k, ensure_ascii=False) + ":" + jcs(v[k]) for k in sorted(v)) + "}"
    raise ValueError("not a JSON value this program writes: %r" % (v,))


def head_of(entries):
    h = bytes(32)
    for i, e in enumerate(entries):
        if e.get("seq") != i + 1:
            raise ValueError("entry %d: sequence number %r" % (i + 1, e.get("seq")))
        h = hashlib.sha256(h + hashlib.sha256(jcs(e).encode()).digest()).digest()
    return h


def eth_call(rpc, to, data):
    req = urllib.request.Request(rpc, json.dumps({"jsonrpc": "2.0", "id": 1, "method": "eth_call", "params": [{"to": to, "data": data, "gas": "0x2faf080"}, "latest"]}).encode(), {"Content-Type": "application/json", "User-Agent": "verify_journal/1"})
    return json.load(urllib.request.urlopen(req, timeout=60))["result"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("answer")
    ap.add_argument("--nonce", required=True)
    ap.add_argument("--rpc")
    ap.add_argument("--dcap")
    ap.add_argument("--compose-hash")
    a = ap.parse_args()
    ans = json.load(open(a.answer))
    entries = ans["entries"]
    nonce = bytes.fromhex(a.nonce.removeprefix("0x"))
    if len(nonce) != 32 or ans["nonce"].lower() != a.nonce.lower():
        sys.exit("FAIL: not the nonce you chose")
    if ans["length"] != len(entries):
        sys.exit("FAIL: length")
    head = head_of(entries)
    if "0x" + head.hex() != ans["head"].lower():
        sys.exit("FAIL: the entries do not give the stated head")
    bound = hashlib.sha256(TAG + head + len(entries).to_bytes(32, "big") + nonce).digest()
    rd = bound + TAG
    quote = bytes.fromhex(ans["quote"].removeprefix("0x"))
    if quote[48 + 520:48 + 584] != rd:
        sys.exit("FAIL: the quote's report data does not bind this journal and nonce")
    print("chain: %d entries, head 0x%s, bound to your nonce in the quote" % (len(entries), head.hex()))
    if not a.rpc:
        print("quote not checked against Intel (no --rpc): this alone proves nothing about the machine")
        return
    pad = b"\0" * ((32 - len(quote) % 32) % 32)
    data = "0x" + SELECTOR + (32).to_bytes(32, "big").hex() + len(quote).to_bytes(32, "big").hex() + (quote + pad).hex()
    raw = bytes.fromhex(eth_call(a.rpc, a.dcap, data)[2:])
    if int.from_bytes(raw[:32], "big") != 1:
        sys.exit("FAIL: the DCAP verifier does not call the quote genuine")
    out = raw[96:96 + int.from_bytes(raw[64:96], "big")]
    if int.from_bytes(out[2:4], "big") != 2 or out[OUT_BODY + 120] != 0:
        sys.exit("FAIL: not a TDX quote of a production machine")
    if out[OUT_BODY + 520:OUT_BODY + 584] != rd:
        sys.exit("FAIL: verified report data differs")
    # dstack writes 0x01 || compose hash into MRCONFIGID (our verifiers on chain read it there).
    if out[OUT_BODY + 184:OUT_BODY + 232] != bytes([1]) + bytes.fromhex(a.compose_hash) + bytes(15):
        sys.exit("FAIL: MRCONFIGID does not name the program %s" % a.compose_hash)
    if ans.get("eventLog"):
        mr = bytes(48)
        composes = []
        for e in ans["eventLog"]:
            if e.get("imr") != 3:
                continue
            mr = hashlib.sha384(mr + bytes.fromhex(e["digest"])).digest()
            if e.get("event") == "compose-hash":
                composes.append(e["event_payload"])
        if mr != out[OUT_BODY + 472:OUT_BODY + 520]:
            sys.exit("FAIL: the event log does not replay to RTMR3")
        if composes != [a.compose_hash]:
            sys.exit("FAIL: compose hash %r in the event log, expected %s" % (composes, a.compose_hash))
    print("quote: genuine (security level %d), production machine, program %s" % (out[4], a.compose_hash))


if __name__ == "__main__":
    main()
