# Contributing

Issues and pull requests are welcome. This is a research prototype: clarity and
proof matter more than features.

## Setup

```sh
npm ci
git clone --depth 1 --branch v1.9.7 https://github.com/foundry-rs/forge-std lib/forge-std
forge test
```

Foundry v1.5.1 and solc 0.8.28 are what the automated checks use.

## The rules a change must meet

1. **The standard stays small.** `src/ERC721AgentOnly.sol` holds three rules.
   Anything else lives around it (registry, accounts, venues, verifiers) and can
   be replaced without touching it.
2. **Every line added has a test that fails without it.** `tools/mutate.py`
   checks this: it disables each guard in turn, applies the changes listed in
   `tools/mutations.json`, and fails if the test suite does not notice.
3. **Nothing is claimed without proof.** A figure in the documentation is either
   generated (`tools/figures.py`), a transaction on a public chain, or a source
   that was read.
4. **No secret in the repository**: no private key, seed or API key, including
   for test networks.

## Checks to run before a pull request

| Command | What it checks |
| --- | --- |
| `forge fmt --check src` | Formatting of the contracts |
| `forge test` | Unit, fuzz and invariant tests |
| `forge test --isolate --match-contract GasTest` | Rewrites `snapshots/Gas.json`, the gas of each operation. The automated check fails if the committed file differs from what this command writes |
| `python3 tools/figures.py` | Figures quoted in the documentation; `--write` updates them |
| `python3 tools/deployments.py` | Every address cited is in `deployments/base-sepolia.json` |
| `halmos --match-contract "AgentOnlyProps\|RegistryProps"` | Symbolic proofs (Halmos 0.3.3) |
| `python3 tools/slither_check.py slither.json` | Slither report against `tools/slither-accepted.json` (see the workflow for the Slither command) |
| `python3 tools/mutate.py` | Mutation testing; about half an hour |

The first seven run on every push and pull request. The fork tests against Base
Sepolia run every night, mutation testing every week.

## License

Contributions are released under CC0-1.0, like the rest of the repository
(third-party files keep their own license, noted next to them).
