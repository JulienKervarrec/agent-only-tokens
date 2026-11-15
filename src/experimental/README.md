# Experimental

Code in this folder is newer and less reviewed than the standard itself
(`../ERC721AgentOnly.sol` and the contracts next to it). Nothing in the
standard depends on it: the registry only sees an optional enrollment
verifier, any contract that answers ERC-1271.

| File | What it does |
| --- | --- |
| `TdxQuoteVerifier.sol` | Checks shared by the hardware verifiers |
| `TdxEnrollmentVerifier.sol` | Enrollment by Intel TDX attestation, fixed measurements |
| `DstackEnrollmentVerifier.sol` | Enrollment of agents on dstack, by event-log replay |
| `Sha384.sol` | SHA-384, needed by the dstack verifier |

Tests and fixtures: `../../test/experimental`. What was checked and what was
not: section 3.11 of `../../docs/study.md`.
