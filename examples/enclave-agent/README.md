# Enclave agent: the first agent enrolled by hardware attestation

A minimal agent program for a dstack confidential VM (Intel TDX), and the record
of its first real run, on 16 November 2026: the key was created inside the
machine, the machine's quote was verified on Base Sepolia by Automata's DCAP
verifier and by `DstackEnrollmentVerifier`, and the registry enrolled the key
with no attester signature. The agent then minted an agent-only token. The
machine was restarted to rotate the key the same way, and a modified build of
the program was refused.

A second program (`v2/`) ran the same day on another machine: enrolled through
the simpler `DstackConfigIdVerifier`, it paid for a public x402 page in USDC,
four times, from its agent account. See "Second program: an agent that pays".

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
  (`MRCONFIGID` = `01`, the hash, padding). A verifier can read the code
  identity there, with no event log and no SHA-384: that became
  `DstackConfigIdVerifier`, used by the second program below.
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
- One provider, one day. The second program ran on another machine of that
  provider, which measured the same base image; the same build was never run
  on two machines at once.

## Second program: an agent that pays

`v2/agent.js` (194 lines, no dependency) is the first program plus two
endpoints. It is embedded whole in `v2/docker-compose.yml`, like the first.

- `GET /buy?account=` buys one page, fixed in the code:
  `https://x402.org/protected`, the public x402 demonstration page. The agent
  asks for the page, receives HTTP 402, and accepts the offer only if it is an
  `exact` payment on Base Sepolia, in USDC, of at most 0.02 USDC. It signs the
  EIP-3009 authorisation as a message of its agent account and sends the
  request again with the payment. The caller chooses the paying account and
  nothing else: not the shop, not the token, not the amount.
- `GET /manifest` returns the outline of the manifest dstack measured.

Before the run it was tested on a local chain against the x402 reference
facilitator and a merchant: 0.01 USDC paid, and an offer above the cap refused.

### Everything was fixed before the machine existed

| Prepared beforehand | How |
| --- | --- |
| Compose hash `580353bb…7ef8` | Shown by the provider's "prepare" step, which deploys nothing |
| Code identity `0x4b20b334…72fc` | Computed from the first machine's quote, changing only the compose hash in `MRCONFIGID` |
| `DstackConfigIdVerifier` approving that identity only | [`0xB47e…502A`](https://sepolia.basescan.org/address/0xB47e270E54Af5BE363BF7F3b897AB85502F3502A) |
| `AttestedAgentRegistry` requiring that verifier | [`0x1410…4059`](https://sepolia.basescan.org/address/0x14109C95422f1ce356521A475eE449e7e7D14059) |
| The agent's future account, from the registry and the agent id | [`0xa1e1…8899`](https://sepolia.basescan.org/address/0xa1e1d2eCeFCCA827F866E3724fC5a577254e8899) |
| 20 test USDC sent to that address | Circle's faucet. The account did not exist yet, and neither did its key |

### The run

Machine: Phala Cloud, `tdx.small`, dstack OS 0.5.12, Phala KMS, about twenty
minutes. It was not the machine of the first run: the platform certificate in
the quote and the attestation key differ. Attributes, MRTD and RTMR0 to RTMR2
are byte for byte those of the first machine.

| Step | Result |
| --- | --- |
| Quote from the machine | Compose hash and code identity equal to the ones prepared |
| Automata DCAP verifier on Base Sepolia | Quote genuine, platform level 0 |
| `DstackConfigIdVerifier.attest`, the quote alone | [tx](https://sepolia.basescan.org/tx/0xac4c5fe0debd7322a151ce1fc962bf445c8f9bd4a555efcf8bbfa8da0f12f268), 3,719,444 gas (4,777,969 with the event log in the first run) |
| `AttestedAgentRegistry.enroll`, no attester signature | [tx](https://sepolia.basescan.org/tx/0x0e38885b28658477fa07fb4d9240739a1ce72c742ebf88dcf6ba0b71ed87a2cd), 199,382 gas. The account appears at the prepared address, with its 20 USDC |
| **The agent buys the page** | HTTP 200 and the page. [Payment](https://sepolia.basescan.org/tx/0x89e0a73920d855494cbad29a8ec0035a4e07c84da12e409b6c1e2f74aade5ea0): 0.01 USDC from the agent account to the merchant, sent by the hosted facilitator, 98,705 gas |
| A second purchase | [Paid](https://sepolia.basescan.org/tx/0x0a23924fed1d2272071bada918d75da60298b63705b2a98534ae93a2ed71f914) |
| The sponsor freezes the agent ([tx](https://sepolia.basescan.org/tx/0x8e55e045a422f3073e56e17964cfdff3af783f5dcd2ea1ad2dd6284c9f02fb3e)), the agent buys | Refused by the facilitator: `invalid_exact_evm_signature`. Balance unchanged |
| Unfrozen ([tx](https://sepolia.basescan.org/tx/0x56daf98c5adeb365e3712aff85f0e2e451670f83346d339ca66f8799e850b445)), the agent buys | [Paid](https://sepolia.basescan.org/tx/0x216e790187dce65c541318318e2aa930409a2d5aad0babc8a09462025efbd797) |
| The agent asked to pay from the first run's agent account, then from a plain wallet | Refused both times: `invalid_exact_evm_signature` |
| Restart: a new key. It buys before being enrolled | Refused. Balance unchanged |
| New quote verified, then key rotation | [attest](https://sepolia.basescan.org/tx/0x7945c84e6a65a687d95fcf5a6e6213a17bc791e82dbe8f4047e527441f37d920) 3,719,420 gas, [rotation](https://sepolia.basescan.org/tx/0x49c322020ed96cc59537c0d7c138bed963d4827fd6e897ad90762257080e9fb7) 43,694 gas. Same account, same USDC |
| The new key buys | [Paid](https://sepolia.basescan.org/tx/0xc9d1118cfdd7647e082a1a207cb35f0c16617e9d108d7a3073d88efb84cdf3b8) |
| The agent mints a token holding the hash of that payment | [tx](https://sepolia.basescan.org/tx/0xe1f1beb4b3574d35014dbae49c304913eb8c8df10aaa97276b51df6aed28d51f), 161,006 gas, collection [`0x7b30…D555`](https://sepolia.basescan.org/address/0x7b302B9c096Ed23115b34E67C070B9f3f839D555) |

Four payments: the account went from 20 to 19.96 USDC. Neither the account
nor its keys ever held ETH. Session keys: `0x994dadcf96c65281042cfaf3bad91cb004045aa7`,
then `0x162af93a704dd852e33aed1e41d3490c89333b95`.

`run-2026-11-16-x402/` holds the two quotes, the event names and payloads, and
the event digests.

### What this run adds

- **A hosted facilitator accepts a payer that is a contract.** The x402.org
  facilitator verified the agent account's signature through ERC-1271 and
  settled with USDC's `transferWithAuthorization`. Until then this had only
  been shown on a local chain with the reference code.
- **The code identity does not depend on the machine.** It was computed from
  one machine's quote and found on another.
- **An agent's money follows the agent, not the key.** The account was funded
  before any key existed, and a new key spent from it after a restart.
- **The emergency stop also stops payments**, at the facilitator: nothing is
  sent to the chain.
- USDC on Base Sepolia runs the code this repository tests against
  (`examples/x402/check-usdc.mjs`, block 59,533,350: identical).
- The manifest's `name` field is empty: the name given to the deployment is
  not measured. The manifest is 33,694 bytes; its compose file has the SHA-256
  of `v2/docker-compose.yml`, and its pre-launch script that of the first run.

### Limits of this run

- One shop, a demonstration page, on a test network, with a test facilitator.
  A production facilitator may run other code or add its own rules.
- The very first request to the shop came back as HTTP 502 and the agent gave
  up; the next request passed. The program does not retry.
- In the answer of `/buy`, `paid` is the offer the agent signed for. The
  payment happened only if `receipt.success` is true.
- Anyone who can reach the machine can make the agent buy that page, up to the
  account's balance. The policy bounds where the money goes and how much per
  purchase, not how often.
- The limits of the first run still apply: pre-launch script not reviewed,
  manifest not archived, base image not rebuilt.
