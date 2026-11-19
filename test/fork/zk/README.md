# A real zero-knowledge proof of a TDX quote check

`sp1-v3-proof.hex` and `sp1-v3-public-values.hex` come from the test fixture
`go-sdk/packages/godcap/sp1/client_api_test.go` of
[automata-dcap-attestation](https://github.com/automata-network/automata-dcap-attestation)
at commit `5962363`: an SP1 v3.0.0 Groth16 proof that Automata's DCAP program
verified an Intel TDX quote. The public values (799 bytes) are that program's
output; their SHA-256, cut to 253 bits, is the proof's second public input
(checked). The proof file is the 4-byte verifier selector followed by the
256-byte proof. Program key:
`0x0043e4e0c286cf4a2c03472ca2384f35a008558bc5de4e0f39d1d1bc989badca`.

SP1 versions before 4.0.0 had soundness bugs (advisory GHSA-c873-wfhp-wx5m);
Succinct froze their verifier routes. This proof shows the mechanics and the
cost on Base Sepolia, not a route to use.

## Our own proof (RISC Zero, step 2.2)

`risc0-seal.hex` (the 4-byte selector `73c457ba`, then the 256-byte Groth16
proof) and `risc0-journal.hex` (797 bytes) are a real proof that Automata's
DCAP v1.1 program (image id `0xcc80…9695`) checked our own dstack quote at
`1794946769` (17 November 2026, 20:19:29 UTC). Made with
[`research/zk-proof`](../../../research/zk-proof/README.md); accepted by the
live RISC Zero router of Base Sepolia. Used by `ZkRealProofBaseSepolia.t.sol`.

## The agent's second proof (step 2.3)

`switch-seal.hex` and `switch-journal.hex`: a real proof of the quote the
agent of section 3.21 made on 18 November 2026 for its next enrollment (nonce
2, key `0xeb12…31f8`, digest `0xf375…2f21`), checked at `1794984098`
(06:41:38 UTC). The prover fetched the quote from the agent itself. Recorded on
chain by `attestWithProof`
([tx](https://sepolia.basescan.org/tx/0x665e2d4a810981f78e7a5049115eee84208461eb957590b43c19e5239e5635f7));
used by `ZkSwitchBaseSepolia.t.sol`.
