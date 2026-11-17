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
| `DstackConfigIdVerifier.sol` | Enrollment of agents on dstack from the quote alone, by `MRCONFIGID` (formats 1 to 3) |
| `Sha384.sol` | SHA-384, needed by the dstack verifier |
| `DstackConfigIdZkVerifier.sol` | The same, with a second route: a RISC Zero proof that Automata's program checked the quote |
| `DualKey.sol` | A session key held by two machines: acts only when both sign |

Tests and fixtures: `../../test/experimental`. What was checked and what was
not: sections 3.11, 3.14, 3.22, 3.24 and 3.26 of `../../docs/study.md`.
