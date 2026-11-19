"""Builds docs/monitor/index.html, the registry monitor, from docs/monitor/template.html.

    python3 tools/monitor_page.py           writes the page
    python3 tools/monitor_page.py --check   fails if the page is not what the template gives

The list of registries comes from deployments/base-sepolia.json. Every event topic and
function selector written in the page is recomputed with `cast` and must match.
"""
import json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
template = (ROOT / "docs/monitor/template.html").read_text()
deployments = json.loads((ROOT / "deployments/base-sepolia.json").read_text())
registries = [{"address": c["address"], "block": c["block"], "run": c["run"]}
              for c in deployments["contracts"] if c["name"].startswith("AttestedAgentRegistry")]

EVENTS = {
    "Enrolled": "Enrolled(uint256,address,bytes32)", "FrozenSet": "FrozenSet(uint256,bool)",
    "Revoked": "Revoked(uint256)", "Retired": "Retired(uint256)", "BondWithdrawn": "BondWithdrawn(uint256,uint256)",
    "VenueSet": "VenueSet(address,bool,bytes32,uint64)", "EnrollmentVerifierSet": "EnrollmentVerifierSet(address,bytes32,uint64)",
    "EnrollmentsHalted": "EnrollmentsHalted(address,bytes32)", "AttestersSet": "AttestersSet(uint256,address[],uint256,bytes32,uint64)",
}
ARGS = {"keyOf": "uint256", "accountOf": "uint256", "isAgent": "address", "isVenue": "address", "venueSince": "address", "enrollmentNonce": "uint256"}
cast = lambda *a: subprocess.run(["cast", *a], capture_output=True, text=True, check=True).stdout.strip()

problems = []
for topic, name in re.findall(r'"(0x[0-9a-f]{64})": "(\w+)"', template):
    if cast("keccak", EVENTS[name]) != topic:
        problems.append(f"topic of {name} is wrong")
for name, sel in re.findall(r"(\w+): \"(0x[0-9a-f]{8})\"", template):
    if cast("sig", f"{name}({ARGS.get(name, '')})") != sel:
        problems.append(f"selector of {name} is wrong")
# Every event and function the page uses exists in the registry's source.
source = (ROOT / "src/AttestedAgentRegistry.sol").read_text().replace(" indexed", "")
for name, sig in EVENTS.items():
    if f"event {name}(" not in source:
        problems.append(f"the registry has no event {name}")
page = template.replace("/*REGISTRIES*/[]", json.dumps(registries))
out = ROOT / "docs/monitor/index.html"
if "--check" in sys.argv:
    if not out.exists() or out.read_text() != page:
        problems.append("docs/monitor/index.html is not up to date: run python3 tools/monitor_page.py")
else:
    out.write_text(page)
for p in problems:
    print(p)
print(f"{len(registries)} registries, {len(EVENTS)} events, {len(problems)} problem(s)")
sys.exit(1 if problems else 0)
