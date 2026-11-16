# Security

This repository is a research prototype. Its contracts are **unaudited drafts**,
deployed on the Base Sepolia test network only. Do not use them with real
assets.

## Reporting a weakness

Please report it privately, through GitHub's
[private vulnerability reporting](https://github.com/JulienKervarrec/agent-only-tokens/security/advisories/new)
("Security" tab, "Report a vulnerability"). A report is most useful with:

- the contract and function concerned;
- a Foundry test that shows the problem (the existing tests in `test/` are a
  good starting point);
- what an attacker gains.

There is no bug bounty. Reports are credited in the study's review log unless
you ask otherwise.

## What counts

The three rules of the standard (`src/ERC721AgentOnly.sol`), the registry, the
agent account and the venues are in scope. So is anything that lets a human-held
key hold, receive or move an agent-only token, or lets an agent lose a token it
did not give up.

Known limits are listed in the README ("Known limits") and in section 7 of
`docs/study.md`; a report that restates one of them is still welcome if it shows
a consequence that is not written there.

## What is checked on every change

Unit, fuzz and invariant tests; symbolic proofs (Halmos); static analysis
(Slither, against a list of accepted findings in `tools/slither-accepted.json`);
and, every week, mutation testing (`tools/mutate.py`). See `CONTRIBUTING.md`.
