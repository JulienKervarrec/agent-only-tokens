# The corrected seventh program on dstack OS 0.6.4, through the document verifier, 23 November 2026

One Phala Cloud machine (dstack 0.6.4, `tdx.small`, our pre-launch script) running
`docker-compose.yml` of this folder: the seventh program as corrected after the independent
review (study section 3.45), the agent and the holder-only service side by side. About
4 minutes, about 0.01 $ of credit, then deleted. The key given for the model gateway was a
placeholder: this run asks the model nothing.

## Approved before the machine existed

The program was approved first: a `DstackDocumentVerifier` (study section 3.46) at
`0x9fcf0cD5C609d8F1484BC2f65FDFF7BA483F5036`, deployed with one identity, computed from the
base image of the 0.6.4 machine of that morning, the compose hash of the corrected program
under the version 3 manifest and the key provider:

    python3 ../manifest/compose-hash.py docker-compose.yml ../manifest/prelaunch-ours.sh --allow PHALA_AI_API_KEY --v3 <key provider id>
    6287ca69b23ae22a57b5f5a9c422365f5dfe30208299a78a040851962e2c6be6

It names no machine. Two attesters announced it for the registry of the sixth run
(transaction `0xd2b9adf4cb371289c7d19f7f13955e3f35f223d32a923c554b826542a9778ba6`, block
62659041). Phala Cloud then showed that same compose hash before deployment.

## The machine

Application `0a3940401db9cf6b2d62c21274cf2b098adeba9b`, instance
`da89193eb38dea8c44ef5eb3531eae40b43bfc40` (from the event log of its quote). Its `MRCONFIGID`
is `03dfe1dc8e0859e54387f7372e893136d2be4c74a2e9f9b48db0f049ccdc5c23c5`, then zeros: what the
contract computes for that application, that instance, that compose hash and that key provider
(`configIdOf`). Same MRTD and RTMR0 to RTMR2 as the machine of that morning.

`os064-enroll.hex` is the enrollment quote as submitted to the chain. Automata's verifier
called it genuine, platform up to date; the document verifier accepted it
(transaction `0xebf5480f207abd04c7869f8ef0fc4269142bec0402dab5db3e74c40fae2727d4`, block
62659817) and the key was enrolled for agent 1 with no attester signature
(`0x948ff3ca6a85a86c52afa4816b0198d795aa0bb805a1fb2f7e43aa69f8fc0170`, block 62659829). One
64-byte field of the file, the quoting enclave's signature of its own report, is the one of
the morning's quote: both are signatures of the same report, and the bytes the machine itself
returned for that field were not kept. (Not named `quote…`: the nightly check compares those
with the 0.5 images.)

## What the corrected program did

- The agent signed in once and was served, free; balance unchanged (0.01 USDC).
- `GET //` on the agent's public port: answered 400, and the agent went on. The same on the
  service: 400, still serving. Before the correction either request stopped the program.
- A sign-in with a wrong signature to a fresh challenge: refused (`signature refused by the
  account`). The same challenge used again, twice at the same moment: refused both times
  (`nonce unknown or already used`): a challenge gives one attempt.
- The service's public counters show the SHA-256 of the last accepted header, not the header.
- `journal.json` is the journal, answered to our nonce `0x7c1e4b9a…4a5b`: two entries. The
  sign-in entry now holds every field of the message, and its hash is recomputed from them.

      python3 ../../../tools/verify_journal.py journal.json --nonce 0x7c1e4b9a02d35f6688aa1c0de9f4b3721a5d6e8f90b1c2d3e4f5061728394a5b

  With `--rpc`, `--dcap`, `--compose-hash`, `--document <application> <instance> <key provider id>`
  and `--verifier` it also said, that day: quote genuine (level 0), production machine, program
  `6287ca69…6be6`, image and program approved by the document verifier. The event log of the
  journal's quote was not kept.

Not tried on the real machine: a flood of challenges (ten thousand requests through Phala's
gateway), a replay of an accepted sign-in (the service no longer shows the header), a refused
sign-in by the agent itself. The local test covers the first two.
