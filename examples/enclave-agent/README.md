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

A third program (`v3/`) fixes three defects of the second. Its compose hash was
computed from this repository before it was deployed: `manifest/` rebuilds the
manifest dstack measures. See "Rebuilding the compose hash" and "Third program".

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

- **The manifest was not archived at the time.** It has since been rebuilt
  from this repository, for this build and the modified one: see "Rebuilding
  the compose hash".
- **Phala's pre-launch script runs before the program** and is part of what the
  compose hash approves. It was reviewed afterwards: same section.
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
- The first three limits above are fixed in the third program.
- As in the first run, the base image was not rebuilt.

## Rebuilding the compose hash

`manifest/` holds Phala Cloud's default pre-launch script, which is public, and
`compose-hash.py`, which rebuilds the manifest dstack measures. It gives the
compose hash of each of the four programs of this folder, as the machines
measured them. A compose hash can therefore be checked, and predicted, from
this repository alone.

### What the pre-launch script does

It was read line by line (406 lines, version 0.0.21). It runs inside the
machine, before the program.

- It logs in to a private registry when credentials are given, removes unused
  images, and pulls the images the compose file names. Our image is pinned by
  digest and the program is in the compose file itself, so a pull cannot
  change it.
- It sets a root password, random unless one is given.
- It writes SSH keys for root, then exports the application id.

Two of its inputs come from whoever deploys or hosts the machine:

- **Environment variables** (registry credentials, root password, SSH keys).
  None reaches the machine in our runs: `allowed_envs` is empty, and that field
  is part of the measured manifest.
- **`/dstack/user_config`.** dstack stores this file without measuring it, and
  the script adds the SSH keys it lists to root's authorized keys. The boot log
  of the third run reads "Set root authorized_keys from user preferences, total
  0 keys": none was installed. But a quote does not say how many were.

What protects the agent's key is therefore the base image: our runs used the
production image, which the provider presents as having no SSH access, and
which is part of the code identity the verifier approves. A development image
has other boot measurements and would be refused. Checked on 17 November
2026: the published production image starts no SSH server and allows no
console login (study, section 3.20). Since the same day our machine runs a
pre-launch script of our own, which installs no key at all (below).

## Third program: retries, a clear answer, a budget

`v3/agent.js` (222 lines, no dependency) is the second program with three
changes.

| Defect of the second program | Change |
| --- | --- |
| It gave up when the shop answered an error once | A request to the shop is sent up to three times when the shop or the network fails. A payment is sent again unchanged: it keeps its nonce, so it can be settled once at most |
| `paid` was filled in even when the payment was refused | The answer has `settled` (true only with the shop's receipt), `signed` (what the agent authorised) and `budgetLeft` |
| Nothing bounded how much a caller could make it spend | A budget of 0.05 USDC for the life of the key. Every signed payment counts, settled or not, because a signed payment can be settled until it expires. A restart clears the count and destroys the key; the new key cannot pay until the sponsor enrolls it |

Tested first on a local chain against the x402 reference facilitator, with a
shop that fails on purpose: seven checks out of seven (one failure before the
payment request, two on the paid request, a shop that stays down, a refused
payer, the budget reached, a restart, an offer above the cap).

At the time, a new program was a new agent: verifier `0x7533…33a6` approves
this identity only, registry `0x49C5…6F9B` requires that verifier, and the
account is new. "Upgrading the program" below removes that constraint.

### The run

Same machine as the second run, restarted with the new compose file.

| Step | Result |
| --- | --- |
| Compose hash, computed from this repository before deployment | `494249cb35c479595b27b20728f8dbd264c68fb84a0a5e17e0c48ad6c5a500a3`. The provider, then the machine, gave the same value |
| Code identity, computed from that hash and a quote of the second run | `0x757cbc54…14d5`, found in the machine's quote |
| `DstackConfigIdVerifier.attest` | [tx](https://sepolia.basescan.org/tx/0xb45304401f2764824fffd3af7efccda99c89353e94110ea695926cfebab008b2), 3,719,408 gas |
| `AttestedAgentRegistry.enroll`, no attester signature | [tx](https://sepolia.basescan.org/tx/0x4fc2101c5ef4e9d7ab1f1c06b50af27904d95eed6963ef61448b55a25727378e), 199,370 gas. The account appears at the address computed beforehand, [`0xbB05…973C`](https://sepolia.basescan.org/address/0xbB052D067E60A1ceE1F15CAb44AE79548C86973C) |
| The agent buys while its account is empty | Refused by the facilitator: `invalid_exact_evm_insufficient_balance`. The answer says `settled: false`, and the budget is charged |
| Four more attempts | Refused the same way; the budget reaches zero |
| Two more attempts | The program refuses to sign: `budget spent` |
| The machine is stopped, the account receives 20 test USDC, the machine restarts | A new key, `0xa4aa2de44036ee4bcf53eb6dff00a6489d8dacae`, and a fresh count. It buys before being enrolled: refused, `invalid_exact_evm_signature` |
| New quote verified, then key rotation | [attest](https://sepolia.basescan.org/tx/0x6c7d566d6f70bea9d5ca071d64caa3a58f195a677930c943c5a887baaeded31e) 3,719,432 gas, [rotation](https://sepolia.basescan.org/tx/0x7697a4575335cf7cdd6b5502d1c999fc82bc4403103150c56d3df820efd1fcf7) 43,670 gas |
| Four purchases | Paid, `settled: true` each time, 98,705 gas each for the facilitator ([first](https://sepolia.basescan.org/tx/0xeb9af69f1d33e8939ae407097ea5c54b93b9d151fbbe0993920faa368c63dbfa), [fourth](https://sepolia.basescan.org/tx/0x2ca56538e4a2332da6737acb1be2e93f8e2bfe3384ff576d800006fd8d1875d8)). The account holds 19.96 USDC |
| Two more attempts | The program refuses to sign: `budget spent`. The refused purchase before the rotation had used one fifth of the budget |

Verifier [`0x7533…33a6`](https://sepolia.basescan.org/address/0x7533FeA85dE4eB3EEf26099051cbc3F32FAB33a6),
registry [`0x49C5…6F9B`](https://sepolia.basescan.org/address/0x49C5C80483dE27FD33e1a570e3BF106dEa9B6F9B).
First session key `0xaf69f5946c2458fc1e6aa32040696b45f0b7a9b9`.
`run-2026-11-16-v3/` holds the two quotes, the event names and payloads, and
the event digests.

The retry could not be provoked on the public shop: it answered every request
of this run. It is covered by the local test only.

### Limits of the third program

- Anyone who can reach the machine can still spend the key's budget, or use it
  up with payments that fail. The budget bounds the loss; it does not say who
  may ask.
- The count lives in memory. It is as trustworthy as the machine's refusal to
  run other code, no more.
- `settled: false` means the shop gave no receipt. If a shop settled a payment
  and then failed to answer, the money would have moved; the budget counts it
  either way.
- The second agent's 19.96 test USDC stay on its account, which only a machine
  running the second program can use: its registry predates the upgrade rule.

## Upgrading the program

The registry now lets its attesters replace the enrollment verifier
(`setEnrollmentVerifier`). An agent can therefore move from one program to the
next and keep its id, its account and its tokens. Run on the same machine,
first with the second program, then with the third:

| Step | Result |
| --- | --- |
| A registry whose verifier approves the second program only | [`0x2D01…06b3`](https://sepolia.basescan.org/address/0x2D01ac2608DD8e898080C6C6c2ae1d7Ff01106b3) |
| The machine runs the second program; quote verified, agent enrolled ([tx](https://sepolia.basescan.org/tx/0xe9ac0662bbc47b366c2d7b05838a3899df0b00b1d0b02f947c0d8a47e1f3a6e1)) | Account [`0xd960…86ED`](https://sepolia.basescan.org/address/0xd960545936a5D167356D8922C6E45198665786ED) |
| The agent mints ([tx](https://sepolia.basescan.org/tx/0xefc45cb0d57022b76c87e430cf8514d7958023a7dc1b87da1c66dbfcc4a03285)) | One token |
| The machine is updated to the third program: a new key, a new quote, verified by the third program's verifier | The registry still asks the first verifier: enrolling that key is refused (`NotVerified`), and so is its order (`NotKey`) |
| Two of the three attesters replace the verifier ([tx](https://sepolia.basescan.org/tx/0x1e8b0e4211dc25b81e61380caa9442f1cc7163b5a8503e89eb68087456d65df1)) | 68,095 gas. The same signatures sent again are refused (`BadAttester`) |
| The new key is enrolled ([tx](https://sepolia.basescan.org/tx/0xd7068b33141d8984cac30c54b0297c71308fcdf19824b69e16c130eebe0d59f1)) | 45,950 gas. Same agent id, same account |
| The agent mints again ([tx](https://sepolia.basescan.org/tx/0x9224ec4f09d2809fc998540294852080b8b8bb9b5ccb4a5b32fceb756b20477d)) | The account holds both tokens |

Session keys: `0x91d2e66621c2d19eef5cc9a59b1d0c07a2fef310`, then
`0x4fe28108aea6e09c3d490966e7e077ce0167a46b`. The two refusals before the
decision were simulated on the chain's state one block earlier.
`run-2026-11-16-upgrade/` holds the two quotes. The verifiers are those of the
second and third runs, reused as they are: a verifier does not depend on a
registry.

## Our own pre-launch script

`manifest/prelaunch-ours.sh` replaces Phala Cloud's default script. It prints
one line and does nothing else: no registry login, no image pull, no root
password, no SSH key, no file from the host, no environment variable. Phala
Cloud's deployment form accepts a custom script; dstack then measures it with
the rest of the manifest.

Run on 17 November 2026, with the third program unchanged, on Phala Cloud
(`tdx.small`, dstack OS 0.5.12, Phala KMS).

| Step | Result |
| --- | --- |
| Compose hash computed here before deployment (`manifest/compose-hash.py ../v3/docker-compose.yml prelaunch-ours.sh`) | `024261d8…39b5`; Phala Cloud's prepared manifest, then the machine, gave the same value |
| What the machine says it measured (`/manifest`) | The compose file and our script, by their SHA-256; the other fields as in the earlier runs |
| Boot log | `Agent-Only Tokens: no pre-launch step`, then the containers start (`run-2026-11-17-prelaunch/boot-log.txt`) |
| Base image, recomputed by `tools/dstack_image.py` | MRTD, RTMR1 and RTMR2 equal to the published 0.5.12 image |
| Code identity | Predicted from the quote of 16 November by changing only MRCONFIGID; Intel's verifier on Base Sepolia returned the same value |
| Verifier approving that identity, then a registry requiring it | [`0x120D…3A74`](https://sepolia.basescan.org/address/0x120D6d17c744900e94Ef59Fa6123Ac29e82D3A74), [`0xE784…aD52`](https://sepolia.basescan.org/address/0xE78420EDf016b1249F2F8664ab172240C43BaD52) |
| Quote verified on chain ([tx](https://sepolia.basescan.org/tx/0x22347b142a4333ac121c4b274911946b7f35f7c0d689a9a704bec610d06f56ea)) | 3,719,468 gas |
| Agent enrolled, no attester signature ([tx](https://sepolia.basescan.org/tx/0x8cddffe6108189ac7a8201b0c6cc796edf59e063bbf62a00f57b86bb7819dc9e)) | 201,819 gas. Account [`0xD6eC…38e7`](https://sepolia.basescan.org/address/0xD6eC25de098d6f23A8Bc180C1A95B8a1A5c238e7) |
| The third run's quote (Phala's default script) sent to the new verifier | Refused: `UnknownCode`, with the third run's code identity |
| The machine is stopped, then started again | Same manifest, our script's line again in the boot log, a new key |
| New quote verified, then key rotation ([attest](https://sepolia.basescan.org/tx/0x6085d69e6a59d57382fb05f6363e5dc555c4db602d11709b9ba02bd29b651a3c), [rotation](https://sepolia.basescan.org/tx/0xb688489e82c51e24a0b2073a2b0557c2df7af0bd58741bbc5b60b6162a1fac5f)) | 3,719,480 and 46,143 gas. Same account; the new key is the agent's key |

Session keys `0x808ef3634f4df8e607f931ef00b0069af5acf43a`, then
`0x7296ba58669ab91b4707b02f764b0d52bff9853d`. The machine ran for about eleven
minutes in all, then was deleted. `run-2026-11-17-prelaunch/` holds the two
quotes, the event names and payloads, and the boot log.

What changes: the SSH keys of `/dstack/user_config`, which the host supplies
unmeasured, are no longer copied anywhere, and the program's start no longer
depends on 406 lines written by the provider. Everything that runs before the
program is now either dstack's, in the approved base image, or ours, in this
folder.

Limit: Phala Cloud's form still writes the other fields of the manifest, as
before. They are measured, and `compose-hash.py` rebuilds them.

## Fourth program: nothing from outside makes it sign

`v4/agent.js` (step 3.2 of the plan, written on 18 November 2026). The first
three programs signed what their HTTP side was asked for, within fixed shapes:
anyone who could reach the machine could make the agent buy. This one cannot
be asked.

- Its HTTP side only shows its key and its state (`GET /`), the manifest, and
  the enrollment quote of its own key. No path signs anything; any other path
  is refused.
- Every signature comes from its own loop. When its key is the one the
  registry recognises, the loop buys one paid x402 page at most once per
  period, under a cap per purchase. When the account is short, it signs an
  order to draw from its allowance (`AgentAllowance`, study section 3.30) and
  shows it in its state; anyone may relay it (`v4/relay.sh`), paying the gas
  and changing nothing.
- Its settings (chain, registry, agent, allowance, token, cap, periods, node,
  shop) come from the compose file, written literally, so they are measured
  with the program; it refuses to start if one is missing or malformed.
- The budget is no longer in its memory: the allowance holds it. A lying node
  can at worst make it ask for a draw or a payment that the allowance and the
  token refuse.

**Tested end to end on a local chain** (`v4/local/run.sh`, also in the
automatic checks): Circle's USDC code, our registry and `AgentAllowance`, a
stand-in x402 shop, and the program itself. Five paths that would sign
(`/mint`, `/buy`, `/pay`, `/draw`, `/sign`) and every `POST` are refused. Left
alone, the agent drew from its allowance and paid twice for the page, then
stopped at its daily limit. Restarted, hence with a new key enrolled on the
same account, it paid nothing more.

**Prepared for a real machine** (18 November 2026). `v4/make_compose.py` writes
`v4/docker-compose.yml`, the program with its settings for Base Sepolia: a
fresh registry for this run (`0x3cA8…f609`, two of three attesters, a notice
delay of 120 seconds, no verifier until the program's measured code is known)
and its allowance contract (`0x72E9…6ACf`). With our pre-launch script, its
compose hash is
`4ae2d85a34b43fc586666f3fd5501e5d31ad494e5644285b62497cc7ee5a7c1a`
(`manifest/compose-hash.py`).

**Run on a real machine** (19 November 2026, `run-2026-11-19-v4/`): the same
compose hash shown by Phala Cloud and measured by the machine; verifier
[`0xD850…987c`](https://sepolia.basescan.org/address/0xD850afBFFD888b289196ECA2C98a906cC615987c)
set on the registry; key enrolled with no attester signature (account
[`0xbb82…d44F`](https://sepolia.basescan.org/address/0xbb8202d84cC93F2bDb69170F6dFaf03Ee84fd44F)).
The agent drew the day's 0.05 USDC in two orders it signed itself, made five
x402 purchases of 0.01 from `x402.org/protected`, all settled, kept to one per
period, refused every request from outside, and after a restart with a new key
kept the same limit; then it stopped. The machine ran about 1 h 25 min, then
was deleted.
