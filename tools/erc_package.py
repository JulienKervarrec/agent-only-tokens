"""Builds the files of the ERC proposal for the ethereum/ERCs repository, in a given folder.

    python3 tools/erc_package.py OUT

OUT/ERCS/erc-TBD.md is docs/erc/erc-agent-only-tokens.md, and OUT/assets/erc-TBD/ holds the
conformance suite made self-contained: the two interfaces of the proposal are written into it,
so that it depends on nothing but forge-std and OpenZeppelin Contracts. Replace TBD by the
number the editors assign, in the file names and in the text.
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1])
(out / "ERCS").mkdir(parents=True, exist_ok=True)
assets = out / "assets" / "erc-TBD"
assets.mkdir(parents=True, exist_ok=True)

text = (ROOT / "docs/erc/erc-agent-only-tokens.md").read_text()
(out / "ERCS" / "erc-TBD.md").write_text(text.replace("assets/eip-TBD/", "assets/erc-TBD/"))

def body(path):
    """A Solidity file without its licence, pragma and imports."""
    lines = (ROOT / path).read_text().splitlines()
    keep = [l for l in lines if not re.match(r"\s*(// SPDX|pragma |import )", l)]
    return "\n".join(keep).strip() + "\n"

suite = (ROOT / "test/conformance/ERC721AgentOnlyConformance.sol").read_text()
suite = re.sub(r'import \{IAgentRegistry\}[^\n]*\n', "", suite)
suite = re.sub(r'import \{IERC721AgentOnly\}[^\n]*\n', "", suite)
head, rest = suite.split("\n/// A registry for the suite alone", 1)
suite = (head + "\n\n" + body("src/IAgentRegistry.sol") + "\n" + body("src/IERC721AgentOnly.sol")
         + "\n/// A registry for the suite alone" + rest)
suite = re.sub(r"\n{3,}", "\n\n", suite)
(assets / "ERC721AgentOnlyConformance.sol").write_text(suite)
print("written", out / "ERCS" / "erc-TBD.md", "and", assets / "ERC721AgentOnlyConformance.sol")

if "--check" in sys.argv:
    # The reference implementation exactly as printed in the proposal, run through the
    # self-contained suite in a fresh project: the text and the suite cannot drift apart.
    import subprocess, tempfile
    code = text.split("## Reference Implementation")[1].split("```solidity")[1].split("```")[0]
    code = re.sub(r"(// SPDX[^\n]*\n|pragma[^\n]*\n|import[^\n]*\n)", "", code)
    # The printed code declares the two interfaces too; the suite already has them, with the
    # same functions (checked here), so the printed copies are dropped.
    for name in ("IAgentRegistry", "IERC721AgentOnly"):
        printed = re.search(r"interface " + name + r" \{(.*?)\n\}\n", code, re.S)
        if not printed:
            sys.exit("the reference implementation does not declare " + name)
        functions = lambda t: sorted(re.findall(r"function [^;]*;", t))
        suite_block = re.search(r"interface " + name + r" \{(.*?)\n\}\n", suite, re.S).group(1)
        if functions(printed.group(1)) != functions(suite_block):
            sys.exit(name + " differs between the text and the suite")
        code = code.replace(printed.group(0), "")
    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp)
        (t / "test").mkdir()
        (t / "src").mkdir()
        (t / "test" / "ERC721AgentOnlyConformance.sol").write_text((assets / "ERC721AgentOnlyConformance.sol").read_text())
        (t / "test" / "Printed.t.sol").write_text(
            '// SPDX-License-Identifier: CC0-1.0\npragma solidity ^0.8.24;\n'
            'import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";\n'
            'import "./ERC721AgentOnlyConformance.sol";\n' + code + '''
contract Printed is ERC721AgentOnly {
    uint256 public lastId;

    constructor(IAgentRegistry r) ERC721("Printed", "PRN") ERC721AgentOnly(r) {}

    function mint() external returns (uint256 id) {
        id = ++lastId;
        _mint(msg.sender, id);
    }

    function burn(uint256 id) external {
        _checkAuthorized(_ownerOf(id), msg.sender, id);
        _burn(id);
    }
}

contract PrintedConformanceTest is ERC721AgentOnlyConformance {
    function _deploy(IAgentRegistry r) internal override returns (address) {
        return address(new Printed(r));
    }

    function _mintToSelf(address) internal override returns (uint256) {
        return Printed(address(token)).mint();
    }

    function _hasBurn() internal pure override returns (bool) {
        return true;
    }

    function _burn(address, uint256 id) internal override {
        Printed(address(token)).burn(id);
    }
}
''')
        (t / "foundry.toml").write_text(
            '[profile.default]\nsrc = "src"\ntest = "test"\nsolc_version = "0.8.28"\nevm_version = "cancun"\n'
            f'remappings = ["@openzeppelin/contracts/={ROOT}/node_modules/@openzeppelin/contracts/", "forge-std/={ROOT}/lib/forge-std/src/"]\n')
        run = subprocess.run(["forge", "test"], cwd=t, capture_output=True, text=True)
        tail = [l for l in run.stdout.splitlines() if "Suite result" in l or "FAIL" in l]
        print("\n".join(tail) or run.stdout[-2000:] + run.stderr[-2000:])
        sys.exit(run.returncode)
