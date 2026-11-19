"""Keeps a SHA256SUMS file in every folder of recorded data, and checks it.

    python3 tools/datasets.py           writes the SHA256SUMS files
    python3 tools/datasets.py --check   fails if a file changed or a SHA256SUMS is stale

Each folder holds what was recorded on a real machine or chain (quotes, event logs, proofs,
compiled code of third parties). Its README says where it comes from; SHA256SUMS lets anyone
check, with `sha256sum -c SHA256SUMS`, that it is the data the study cites.
"""
import hashlib, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FOLDERS = [
    "test/usdc", "test/fork/zk", "test/experimental/tdx", "test/experimental/phala", "test/experimental/dstack",
    "examples/enclave-agent/run-2026-11-16", "examples/enclave-agent/run-2026-11-16-x402",
    "examples/enclave-agent/run-2026-11-16-v3", "examples/enclave-agent/run-2026-11-16-upgrade",
    "examples/enclave-agent/run-2026-11-17-prelaunch", "examples/enclave-agent/run-2026-11-19-v4",
]
SKIP = {"SHA256SUMS", "README.md", "LICENSE"}

problems = 0
for folder in FOLDERS:
    d = ROOT / folder
    if not (d / "README.md").exists():
        print(f"{folder}: no README.md")
        problems += 1
    lines = [f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n"
             for p in sorted(d.iterdir()) if p.is_file() and p.name not in SKIP]
    text = "".join(lines)
    target = d / "SHA256SUMS"
    if "--check" in sys.argv:
        if not target.exists() or target.read_text() != text:
            print(f"{folder}: SHA256SUMS is missing or stale")
            problems += 1
    else:
        target.write_text(text)
print(f"{len(FOLDERS)} folders, {problems} problem(s)")
sys.exit(1 if problems else 0)
