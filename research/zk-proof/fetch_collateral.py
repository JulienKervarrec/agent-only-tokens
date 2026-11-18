"""Read the Intel collateral for our TDX quote from Automata's on-chain PCCS on Base Sepolia.

Writes raw files into the given directory: root.der, root-crl.der, signing.der,
platform-crl.der, tcb-info.json and qe-identity.json (the same shapes Automata's
pccs-reader builds). Read-only JSON-RPC calls (Python standard library only), no key.
The DAO addresses come from the router the DCAP verifier reads through, not from a list.
"""
import json
import os
import sys
import urllib.request

RPC = os.environ.get("RPC", "https://sepolia.base.org")
ROUTER = "0xaf2a0D5473062b36E2dE986DA09d945EB26d492B"  # Automata PCCS router, Base Sepolia
FMSPC = "20a06f000000"
ROOT, PLATFORM, SIGNING = 0, 2, 3
# Function selectors (keccak of the signature, computed with `cast sig`).
SEL = {
    "tcbEvalDaoAddr()": "0a2c531f",
    "standard(uint8)": "13ec5575",
    "pcsDaoAddr()": "67ecb139",
    "fmspcTcbDaoVersionedAddr(uint32)": "d1ffdd3a",
    "qeIdDaoVersionedAddr(uint32)": "f51e240a",
    "getCertificateById(uint8)": "722f1327",
    "getTcbInfo(uint256,string,uint256)": "cfbc42fb",
    "getEnclaveIdentity(uint256,uint256)": "f0f074f7",
}


def word(n):
    return n.to_bytes(32, "big")


def call(to, sig, data=b""):
    body = {"jsonrpc": "2.0", "id": 1, "method": "eth_call",
            "params": [{"to": to, "data": "0x" + SEL[sig] + data.hex()}, "latest"]}
    req = urllib.request.Request(RPC, json.dumps(body).encode(), {"Content-Type": "application/json", "User-Agent": "aot-zkp/0.1"})
    res = json.load(urllib.request.urlopen(req, timeout=30))
    if "error" in res:
        sys.exit(f"{sig}: {res['error']}")
    return bytes.fromhex(res["result"][2:])


def address(ret):
    return "0x" + ret[12:32].hex()


def uint(ret):
    return int.from_bytes(ret[:32], "big")


def dyn(ret, base, k):
    """The k-th dynamic field (bytes or string) of a tuple encoded at offset base."""
    off = base + int.from_bytes(ret[base + 32 * k: base + 32 * k + 32], "big")
    n = int.from_bytes(ret[off: off + 32], "big")
    return ret[off + 32: off + 32 + n]


def main(out):
    os.makedirs(out, exist_ok=True)
    tcb_eval = uint(call(address(call(ROUTER, "tcbEvalDaoAddr()")), "standard(uint8)", word(1)))
    pcs = address(call(ROUTER, "pcsDaoAddr()"))
    tcb_dao = address(call(ROUTER, "fmspcTcbDaoVersionedAddr(uint32)", word(tcb_eval)))
    qe_dao = address(call(ROUTER, "qeIdDaoVersionedAddr(uint32)", word(tcb_eval)))
    print("standard evaluation", tcb_eval, "pcs", pcs, "tcb", tcb_dao, "qe", qe_dao)

    files = {}
    for name, ca in (("root", ROOT), ("signing", SIGNING), ("platform", PLATFORM)):
        ret = call(pcs, "getCertificateById(uint8)", word(ca))
        files[f"{name}.der"], files[f"{name}-crl.der"] = dyn(ret, 0, 0), dyn(ret, 0, 1)
    fm = FMSPC.encode()
    ret = call(tcb_dao, "getTcbInfo(uint256,string,uint256)",
               word(1) + word(96) + word(3) + word(len(fm)) + fm.ljust(32, b"\0"))
    tcb_str, tcb_sig = dyn(ret, uint(ret), 0), dyn(ret, uint(ret), 1)
    ret = call(qe_dao, "getEnclaveIdentity(uint256,uint256)", word(2) + word(4))
    qe_str, qe_sig = dyn(ret, uint(ret), 0), dyn(ret, uint(ret), 1)
    # The JSON strings are kept byte for byte: the signatures are over them.
    files["tcb-info.json"] = b'{"tcbInfo": ' + tcb_str + b', "signature": "' + tcb_sig.hex().encode() + b'"}'
    files["qe-identity.json"] = b'{"enclaveIdentity": ' + qe_str + b', "signature": "' + qe_sig.hex().encode() + b'"}'
    for k in ("root.der", "root-crl.der", "signing.der", "platform-crl.der", "tcb-info.json", "qe-identity.json"):
        if not files[k]:
            sys.exit(f"empty: {k}")
        with open(os.path.join(out, k), "wb") as f:
            f.write(files[k])
        print(k, len(files[k]))


if __name__ == "__main__":
    main(sys.argv[1])
