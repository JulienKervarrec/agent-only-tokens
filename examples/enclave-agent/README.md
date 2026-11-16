# Enclave agent: the first agent enrolled by hardware attestation

A minimal agent program for a dstack confidential VM (Intel TDX), and the record
of its first real run, on 16 November 2026: the key was created inside the
machine, the machine's quote was verified on Base Sepolia by Automata's DCAP
verifier and by `DstackEnrollmentVerifier`, and the registry enrolled the key
with no attester signature. The agent then minted an agent-only token. The
machine was restarted to rotate the key the same way, and a modified build of
the program was refused.

Test network only. Unaudited. Throwaway test keys paid the gas.

## The program

`agent.js` (149 lines, no dependency) is embedded whole in `docker-compose.yml`,
so the compose hash measured by dstack identifies the program. The image is
pinned by digest and the container's file system is read-only.

- The session key is created in memory at start. It is never written, printed
  or returned.
- `GET /enroll` computes the registry's enrollment digest for that key and asks
  the processor for a quote carrying it. It quotes nothing else.
- `GET /mint` signs one kind of order only: the agent's account calls
  `mint(bytes32)` on a collection. There is no free-form instruction.
- Every parameter has a fixed shape (address, 32 bytes, number); anything else
  is refused.

Before the run it was tested against the real contracts on a local chain, with
a stand-in for the dstack socket: its digest equals the registry's
`hashEnrollment`, an order it signed minted a token, and 60 signed orders out
of 60 recover to its key.

## The run

Machine: Phala Cloud, `tdx.small`, dstack OS 0.5.12 (production image, no SSH),
Phala KMS. Up for about seven minutes, then thirteen more for the second part.

| Step | Result |
| --- | --- |
| Quote from the machine (5,010 bytes, version 4, TDX 1.0 report) | Report data = enrollment digest, then 32 zero bytes. Debug flag off |
| Event log | Ten RTMR3 events; `compose-hash` is the third, `boot-mr-done` the fifth. Replayed with SHA-384, they give the quote's RTMR3 |
| Automata DCAP verifier on Base Sepolia | Quote genuine, platform level 0 (up to date) |
| `DstackEnrollmentVerifier.attest` | [tx](https://sepolia.basescan.org/tx/0x3bde5e7d3ccf206d60290a8b9de98ae72ea5d79f2fc6368141c3e652613b9fcf), 4,777,969 gas |
| `AttestedAgentRegistry.enroll`, no attester signature | [tx](https://sepolia.basescan.org/tx/0x2001f551c48d9b8b279bcfd5a4347bce5a2b1e6dabf4e1c748e8ea719ffeeca2), 199,394 gas |
| The agent mints, its order relayed | [tx](https://sepolia.basescan.org/tx/0x28c4cf5995942e47404d73444b91c485b5045189c9124986e972cc5cbe880c64), 161,006 gas. The agent account and its key hold no ETH |
| Another key, with no quote | Refused: `NotVerified` |
| A plain wallet mints | Refused: `NotAgent` |
| The same order relayed twice | Refused: `NotKey` |

| Contract | Address |
| --- | --- |
| `DstackEnrollmentVerifier` (up-to-date platforms, this code only) | [`0x7C57…86d1`](https://sepolia.basescan.org/address/0x7C5784D4CC4A535d0E840199c941aCb977f686d1) |
| `AttestedAgentRegistry` requiring that verifier | [`0xFd2c…236b`](https://sepolia.basescan.org/address/0xFd2c0D61692E4Ae615E2ab7BA53e0Bb33d81236b) |
| Agent account | [`0xA228…241c`](https://sepolia.basescan.org/address/0xA228bbeCA2cCD2e55FB15bF81e523DCf43e0241c) |
| Collection | [`0x99D2…cCE7`](https://sepolia.basescan.org/address/0x99D26E63f042A3B5ab533f1D3660b8158501cCE7) |

Compose hash: `95b3c3e50b054db593842d68401d342d36136cd7c6002ecedebcdece9608dc21`.
Session key: `0x3b6516b64d6ff8bd1c57f75fd1a1c3956d458844`.

### Second part: restart, rotation, emergency stop, modified build

The machine was stopped, which destroyed the key, then started again.

| Step | Result |
| --- | --- |
| Restart of the same build | A new key, `0xea7e…9a90`; same code identity, same RTMR3 |
| The new key enrolled before its quote is verified, or with the first quote | Refused: `NotVerified` |
| New quote verified, then key rotation | [attest](https://sepolia.basescan.org/tx/0x0cef58e898474e9fec25e07c6403e4366e679c0afb9e10e722b99db022a081e0) 4,777,969 gas, [rotation](https://sepolia.basescan.org/tx/0x3c1a41e3e83ab5ddb090ca46fb9a1433313cc0cde7af30c5c1e6bed38707b7ae) 43,706 gas. Same account, which still holds its token |
| The sponsor freezes the agent ([tx](https://sepolia.basescan.org/tx/0x6be8575fefe51c8ef5d27c849450fb0fa835db12c109147858298be08feb62da)) | A fresh order signed by the enclave is refused: `NotKey` |
| Unfrozen ([tx](https://sepolia.basescan.org/tx/0xe01094416a6476f9ca31bdb08d9fd563ef352c9d979ba168ecbb660cd428d25b)), the same order relayed | [Second token minted](https://sepolia.basescan.org/tx/0x00bff9a8818cb16b10ce11f87a4c2d97f9285eff631ba45764ff161aa361b4e5), 109,706 gas |
| **Modified build** on the same machine (`modified-docker-compose.yml`: one more endpoint) | Compose hash `6b79fe24…1412`. Automata still finds its quote genuine |
| Its quote submitted with its own compose hash | Refused: `UnknownCode` |
| Its quote submitted claiming the approved compose hash, or with the approved build's event log | Refused: `BadEventLog` |

Refusals were simulated on the chain's live state, not sent.

`run-2026-11-16/` holds the three quotes (enrollment, rotation, modified
build), the event names and payloads, and the event digests, as submitted.
`enroll.sh` is the script that sent the first transactions; the later ones were
sent with the same `cast` commands.

## What was learned

- The verifier's assumption holds on a production machine: the OS writes
  `compose-hash` before `boot-mr-done`.
- dstack leaves the digest of RTMR3 events empty in the log it returns; they
  are recomputed from each event's name and payload.
- This dstack version also writes the compose hash into the quote itself
  (`MRCONFIGID` = `01`, the hash, padding). A verifier could read the code
  identity there, with no event log and no SHA-384. Not done here.
- `allowed_envs` is part of the measured manifest and was empty: the machine
  accepts no environment variable from whoever deploys it.
- The compose hash is the SHA-256 of the manifest (`app-compose.json`): the
  modified build computed it from inside the machine and found the measured
  value. That manifest holds 17 fields: the compose file (its SHA-256 equals
  that of the file in this folder), Phala's pre-launch script (18,114 bytes,
  SHA-256 `c452d7122315255914858880fa3d7931f965f57d04631ead4b7164736bcd0765`)
  and settings (`kms_enabled` true, `public_logs` true, `secure_time` false,
  `storage_fs` ext4, `no_instance_id` false, among others).
- Quotes from one machine differ only in the report data and in two
  signatures; the certificate chain is the same.

## Limits

- **The exact manifest was not archived.** Its fields and the hash of each
  long one are listed above, for the modified build; the approved build's
  manifest should differ only by its compose file, which was not checked. The pre-launch script itself is not in
  this repository, so the compose hash cannot be recomputed from it.
- **Phala's pre-launch script runs before the program** and is part of what the
  compose hash approves. It was not reviewed.
- **The base image was taken from the quote**, not rebuilt from dstack's
  sources.
- **Key provider: Phala KMS.** The verifier does not check it; the program
  keeps its key in memory only, so it does not depend on it.
- **The mint policy names no collection:** the agent signs a `mint(bytes32)`
  for any target. Anyone who can reach the machine can ask for such an order.
- **The key died with the machine.** That is the intent (nothing durable to
  steal), but this agent cannot act again until a new machine running the same
  code enrolls a new key.
- One machine, one provider, one day. A second instance of the same build on
  another machine was not tried.
