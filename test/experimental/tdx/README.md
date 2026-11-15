# Sample Intel TDX quote

`quote-v4.hex` is a real Intel TDX attestation quote (version 4, 8,000 bytes),
copied unchanged from the test suite of
[automata-network/automata-dcap-attestation](https://github.com/automata-network/automata-dcap-attestation)
at tag `v1.2.0` (commit `f71d6521cc30806da369c7ee609af47c02b73448`, file
`evm/forge-test/AutomataDcapOnChainAttestationTest.t.sol`, test
`testTDXQuoteV4OnChainAttestation`). That repository is under the MIT licence,
reproduced in `LICENSE`.

The tests in `../TdxEnrollment.t.sol` use it for the layout and the
measurements of a real quote. They do not verify its signature: a stand-in
replaces the DCAP verifier. When a test needs the quote to carry a given
digest, it overwrites the report data, which a real verifier would reject.

keccak256 of the quote: `0xc22f71ddfeb5f49868ee7dddb11830e93c3b2053e01ca990eb84a37805c9ef26`.
