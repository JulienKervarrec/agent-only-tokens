#!/usr/bin/env python3
"""Checks a journal returned by the sixth agent program (GET /journal/quote?nonce=...).

  verify_journal.py ANSWER.json --nonce 0x...            # chain and report data only
  verify_journal.py ANSWER.json --nonce 0x... --rpc URL --dcap ADDRESS --compose-hash HEX
                                                         # plus Intel's check, read-only, on chain
  ... --verifier ADDRESS                                 # plus: the same code as the registry trusts
  ... --document APP INSTANCE KEY_PROVIDER_ID            # dstack OS 0.6 (MRCONFIGID format 3); --verifier is
                                                         # then a DstackDocumentVerifier

It recomputes the hash chain from the entries, checks that the quote's report data binds that
head, that length and the nonce you chose, and, with --rpc, that Automata's DCAP verifier calls the
quote genuine, that the machine is not in debug mode, that its MRCONFIGID names the program (the
compose hash given), and, if the answer carries the event log, that it replays to RTMR3 with exactly
that one compose hash. With --verifier (a DstackConfigIdVerifier, the
registry's enrollment verifier), the whole measured code of the quote, operating system image and
program together, must be one that verifier approves: without it, only the program is checked, not
the system under it. A platform that Intel does not call up to date is refused unless
--accept-level says otherwise. What it proves: the measured program, on that machine, stated this
ordered list of entries when it answered. What it does not: that nothing
happened before the program's last start (a restart begins a new journal), or after the quote.
No dependency beyond the Python standard library.
"""
import argparse, hashlib, json, sys, urllib.request

TAG = hashlib.sha256(b"agent-only-tokens.journal.v1").digest()
SELECTOR = "38d8480a"  # verifyAndAttestOnChain(bytes)
CODE_OF = "1e05758f"  # codeOf(bytes)
IS_APPROVED = "ac127ce4"  # isApprovedCode(bytes32)
IMAGE_OF = "2d9aac00"  # imageOf(bytes), DstackDocumentVerifier
PROGRAM_OF = "caf28659"  # programOf(bytes32,bytes32,bytes), DstackDocumentVerifier
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
    ap.add_argument("--verifier")
    ap.add_argument("--document", nargs=3, metavar=("APP_ID", "INSTANCE_ID", "KEY_PROVIDER_ID"),
                    help="dstack OS 0.6: MRCONFIGID is the hash of a document naming these (hexadecimal); "
                         "--verifier is then a DstackDocumentVerifier")
    ap.add_argument("--accept-level", type=int, default=0, help="highest TCB status accepted (0: up to date)")
    a = ap.parse_args()
    if a.rpc and not (a.dcap and a.compose_hash):
        ap.error("--rpc needs --dcap and --compose-hash")
    if (a.dcap or a.compose_hash or a.verifier) and not a.rpc:
        ap.error("--dcap, --compose-hash and --verifier need --rpc")
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
    if out[4] > a.accept_level:
        sys.exit("FAIL: Intel's status of the platform is %d, above the accepted %d" % (out[4], a.accept_level))
    if a.document:
        # dstack OS 0.6 (format 3): 0x03 || sha256("dstack-mr-config-v3:" 0x00 document), the
        # document being the canonical one DstackDocumentVerifier writes on chain.
        app, instance, provider = (v.lower().removeprefix("0x") for v in a.document)
        document = ('{"app_id":"%s","compose_hash":"%s","init_script_hashes":[],"instance_id":"%s",'
                    '"key_provider":"kms","key_provider_id":"%s","version":3}' % (app, a.compose_hash, instance, provider))
        expected = bytes([3]) + hashlib.sha256(b"dstack-mr-config-v3:\0" + document.encode()).digest() + bytes(15)
    else:
        # dstack OS 0.5 writes 0x01 || compose hash into MRCONFIGID (our verifiers on chain read it there).
        expected = bytes([1]) + bytes.fromhex(a.compose_hash) + bytes(15)
    if out[OUT_BODY + 184:OUT_BODY + 232] != expected:
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
    if a.verifier:
        # codeOf(bytes) then isApprovedCode(bytes32), on the registry's own enrollment verifier.
        opad = b"\0" * ((32 - len(out) % 32) % 32)
        code = eth_call(a.rpc, a.verifier, "0x" + (IMAGE_OF if a.document else CODE_OF) + (32).to_bytes(32, "big").hex() + len(out).to_bytes(32, "big").hex() + (out + opad).hex())
        if a.document:
            # The program: that image, the compose hash and the key provider.
            kp = bytes.fromhex(provider)
            code = eth_call(a.rpc, a.verifier, "0x" + PROGRAM_OF + code[2:] + a.compose_hash + (96).to_bytes(32, "big").hex()
                            + len(kp).to_bytes(32, "big").hex() + (kp + b"\0" * ((32 - len(kp) % 32) % 32)).hex())
        if int(eth_call(a.rpc, a.verifier, "0x" + IS_APPROVED + code[2:]), 16) != 1:
            sys.exit("FAIL: the verifier %s does not approve this code (%s)" % (a.verifier, code))
        print("code: %s, system image and program, approved by %s" % (code, a.verifier))
    else:
        print("system image not checked (no --verifier): only the program's hash was")


if __name__ == "__main__":
    main()
