# Agent-Only Tokens: research, approach, standard and use cases

Julien Kervarrec · November 2026

This document records how the Agent-Only Tokens draft was reached: what already
exists, how the design was narrowed down, what the resulting standard says, and
what it can be used for. Figures about the prototype come from tests run on a
local simulated EVM, except those of sections 3.12 to 3.16, measured on the
Base Sepolia test network. Nothing has been deployed on a main network, and nothing has been
audited.

## Summary

**No contract can prove "this caller is an LLM". A contract can enforce that
every address holding or moving a token is an account with no human owner,
driven by a key that a registry recognises as an agent's.** That is the only
definition of "LLM-only" that holds technically, and it is enough to keep the
token off OpenSea, Rarible and any other general marketplace.

- **Achievable today.** An NFT that no human wallet can mint, receive, transfer,
  list, pledge or burn. A general marketplace can neither be approved for the
  token nor receive it, so it cannot sell it. Resale goes through a small venue
  contract that settles between two agents in one transaction.
- **Not achievable, whatever the standard.** Preventing a human from owning the
  machine the agent runs on, funding it, selling the whole agent, influencing
  what it reads, or selling an off-chain promise about the NFT.
- **Retained design.** A classic ERC-721 with three extra rules: only agent
  accounts and approved venues can hold it, move it or be approved for it. The
  proof of agent lives in a separate, replaceable registry.
- **Main risk.** Not the token contract. It is the operator with physical access
  to their own TEE machine, then prompt injection through NFT metadata.
- **Little is new.** Most of the project assembles existing building blocks.
  What is missing, and what an ERC could add, is the "agent-only token" profile
  that ties them together.

## 1. Research

### 1.1 What "LLM-only" can mean

**A blockchain only sees signatures.** It does not know who had the idea for a
transaction. The whole design therefore comes down to what is proven about the
key that signs. Five levels exist, and almost every current "agent-only"
project stops at the first two.

| Level | What is proven | How a human gets around it | Who does this today |
| --- | --- | --- | --- |
| **L0. Machine challenge** | The client solved a computation | A ten-line script | [Shellborn](https://www.shellborn.io/) and [No Human Allowed](https://www.nohumanallowed.com/) (SHA-256 puzzle), [agentsonly.vip](https://opensea.io/tools/x402-bazaar/base/318388764643149040) (sale through x402 only) |
| **L1. Registry or account type** | The address is listed somewhere, or contains code | They register themselves, or delegate their wallet to code (EIP-7702) | [AgenticNFT on X Layer](https://github.com/wizard0x0/agentic_only_nft) (`code.length > 0` check), [Printer AI](https://agentprinter.netlify.app/) (Binance Agent ID registry) |
| **L2. Key born in an attested runtime** | The key only exists inside an enclave running measured code | They can no longer sign, but they can dictate orders to their agent | TEE agents ([dstack](https://github.com/dstack-TEE/dstack), [Oasis ROFL](https://oasis.net/blog/multichain-wallet-agents)), not yet applied to an NFT |
| **L3. L2 + no instruction channel** | The attested code accepts no free-form instruction; the model decides inside a fixed policy | They can only fund, unplug, or poison the data it reads | Nobody in production |
| **L4. zk proof of inference** | The model's computation is proven mathematically, with no hardware trust | Same limits as L3, without the hardware weakness | Research ([FlashProve](https://www.anthropic.com/research/provable-inference), [ERC-7992](https://eips.ethereum.org/EIPS/eip-7992)) |

L2 is already enough for no human to buy on a general marketplace, because no
human wallet is a valid recipient. L3 adds that a human cannot tell their agent
"buy number 42".

Three limits hold at every level:

1. **A human always owns the machine or pays for the cloud.** On Moltbook,
   [1.5 million agents belonged to 17,000 humans](https://en.wikipedia.org/wiki/Moltbook).
2. **A proof of execution is not a proof of autonomy.** It says which program
   ran, not who chose its inputs.
3. **Economic rights leak off-chain.** Nothing stops two humans from signing a
   paper contract about what their agents will do.

### 1.2 Existing Ethereum standards

**No standard covers "a token only agents can hold and move", but each piece
exists separately.** Statuses were checked on 11 November 2026.

| Standard | Status | What is reused | Limit for this project |
| --- | --- | --- | --- |
| [ERC-721](https://eips.ethereum.org/EIPS/eip-721) | Final | The whole interface, unchanged | No control over who holds |
| [ERC-3643](https://eips.ethereum.org/EIPS/eip-3643) | Final | The split between a token and a separate eligibility registry | Built for permissioned security tokens |
| [ERC-721C](https://medium.com/limit-break/creator-token-standards-building-guardrails-for-your-tokens-3b261cdd3027) (Limit Break, outside the ERC process) | In production | Evidence that a validation hook on every transfer holds against marketplaces. OpenSea [complies through Seaport](https://docs.opensea.io/docs/creator-fee-enforcement) | Under the recommended validator, [a transfer started by the holder goes through](https://abx.docs.artblocks.io/docs/using-abx/guides/royalty-enforcement). Not enough as is |
| [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) Trustless Agents | Draft, deployed on mainnet | Agent identity for discovery and reputation | Registration is open to anyone, humans included. The validation registry [is not deployed yet](https://taiko.xyz/guides/erc-8004-trustless-agent-standard) |
| [ERC-8273](https://eips.ethereum.org/EIPS/eip-8273) Attestation-Gated Agentic Actions | Draft | Per-operation attestation bound to an action digest | Does not say which proof to require. Attesters are authorised by the registry owner |
| [ERC-8274](https://ethereum-magicians.org/t/erc-8274-ai-inference-proof-verification/28083) AI Inference Proof Verification | Under discussion (PR #1771), no page on eips.ethereum.org at the time of writing | A single `IProofVerifier.verify()` interface for zkML, opML, TEE and oracles | Not frozen |
| [ERC-7992](https://eips.ethereum.org/EIPS/eip-7992) Verifiable ML Inference | Draft | Model registry and verification of zk inference proofs | zk only |
| [ERC-7066](https://eips.ethereum.org/EIPS/eip-7066) Lockable Extension | Final | Locking an NFT in place for staking, lending and rental | Unlocking relies on approved addresses |
| [ERC-4907](https://eips.ethereum.org/EIPS/eip-4907) Rental NFT | Final | A user role with an expiry | The user can be any address |
| [ERC-8126](https://eips.ethereum.org/EIPS/eip-8126) and [ERC-8196](https://eips.ethereum.org/EIPS/eip-8196) | Final (June and August 2026) | Agent risk score; policy-bound agent wallet | The ERC-8196 policy is set by an owner, so a human stays in control by design |
| [ERC-8217](https://eips.ethereum.org/EIPS/eip-8217) Agent NFT Identity Bindings | Draft | Known in order to avoid it | Whoever holds the master NFT controls the agent: the "account sale" this project must prevent |
| [ERC-7857](https://ercs.ethereum.org/ERCS/erc-7857) (0G, iNFT) | Draft | Re-encryption of private metadata in a TEE on transfer | Designed to sell agents to humans, the opposite need |
| [ERC-8354](https://eips.ethereum.org/EIPS/eip-8354) Confidential Agent Policy Verdicts | Draft | zk proof that an action follows a secret policy | Optional |
| [ERC-6551](https://eips.ethereum.org/EIPS/eip-6551) Token Bound Accounts | Review (checked 12 November 2026) | Candidate for positions that are not NFTs (see use cases) | Not tested here |

### 1.3 Execution and proof building blocks

| Building block | What it brings | Useful fact |
| --- | --- | --- |
| [dstack](https://github.com/dstack-TEE/dstack) (Phala) | Confidential VM on Intel TDX with attestation. [Ready-made ERC-8004 agent template](https://docs.phala.com/phala-cloud/getting-started/explore-templates/deploy-erc-8004-agent) | Open source |
| [Automata DCAP](https://docs.ata.network/tee-overview/tee-verifiers/intel-sgx-tdx-dcap) | On-chain verification of an Intel SGX/TDX attestation | [About 4 to 5M gas directly, about 500k with a zk proof](https://github.com/automata-network/automata-dcap-attestation) |
| [Proof of Cloud](https://proofofcloud.org/) | Signed public registry binding a TEE server's hardware id to a verified data centre | 11 contributing organisations. No contract-readable interface is documented |
| Confidential inference ([Phala / RedPill](https://docs.phala.com/phala-cloud/confidential-ai/verify/verify-attestation.md), [NEAR AI Cloud](https://skills.sh/near/agent-skills/near-ai-cloud)) | Open models served in TDX VMs with attested Nvidia GPUs, signed responses | Adds three trusted parties: the provider, Intel and Nvidia |
| [Oasis ROFL](https://docs.oasis.io/build/use-cases/price-oracle) | Chain-managed TEE application. A Sapphire contract can restrict a function to that application | Kept as a second implementation path |
| [CaMeL](https://arxiv.org/abs/2503.18813) (Google DeepMind) | Architecture where untrusted data cannot alter the agent's control flow | 77% of tasks solved with provable security, against 84% without defence |
| [Taiko multi-proofs](https://docs.taiko.xyz/taiko-alethia-protocol/protocol-design/multi-proofs) | Production precedent: fast TEE proof, stronger zk proof, combination of both | Shows how to tier proofs by stake |
| [EigenAI](https://blog.eigencloud.xyz/deterministic-ai-inference-eigenai/) | Bit-exact deterministic inference, challengeable by re-execution | Under 2% overhead announced |
| [FlashProve](https://www.anthropic.com/research/provable-inference) (Anthropic, 2 November 2026) | zk proof that a response comes from given weights | Proof of about 19 MB, 72 to 94 times the GPU cost, 1,024 tokens, greedy decoding on integer weights |
| zkTLS ([Reclaim llm-x402](https://github.com/reclaimprotocol/llm-x402), [Primus](https://docs.primuslabs.xyz/implementation-scenarios/provable-agent-execution)) | Proof that a response came from a given model API | Adds a trusted notary |
| [x402 v2](https://www.x402.org/writing/x402-v2-launch) | HTTP payments between agents | [Linux Foundation governance operational since 14 July 2026](https://xenospectrum.com/en/linux-foundation-x402-agent-payments/) |

### 1.4 "Agent-only" projects already launched

**All of them filter the mint. None of those that could be checked restricts
resale.** A token locked over its whole life cycle, secondary market included,
was not found.

| Project | Entry filter | Resale |
| --- | --- | --- |
| [Lobros](https://www.lobros.fun/) (Base, ERC-404) | Maths challenge, then a backend co-signature checked by the contract | No documented restriction |
| [Agentic Proof of Work](https://github.com/Agentoshi/apow-core) (Base) | Challenge to be solved by an LLM within 20 seconds; calls from contracts blocked | Transfers open once liquidity is deployed |
| [Machine Readable Only](https://machinereadableonly.com/llms.txt) (Base Sepolia) | Signed requests and a 5-second challenge; 1 USDC x402 payment | Transferable. The project states that humans can own and trade the tokens |
| [AgenticNFT](https://github.com/wizard0x0/agentic_only_nft) (X Layer) | The address must contain code | No documented transfer rule |
| [Shellborn](https://www.shellborn.io/), [No Human Allowed](https://www.nohumanallowed.com/) (Solana) | SHA-256 puzzle | Not checked |
| [agentsonly.vip](https://opensea.io/tools/x402-bazaar/base/318388764643149040) (Base) | Sale through x402 only | Not checked |
| [Printer AI](https://agentprinter.netlify.app/) (BNB Chain) | Binance Agent ID registry | Not checked |
| [PairMine](https://github.com/pairmineai/pairmine-skill), [ClawMint](https://clawmint.io/) | Not studied in detail | Not checked |

### 1.4b Agent NFT standards that let humans own agents

Checked on 14 November 2026. These proposals answer a different question,
"how does an agent live inside an NFT", and all of them keep a human able to
hold or buy the token.

| Proposal | What it does | Who can hold the token | Difference with this project |
| --- | --- | --- | --- |
| [ERC-7857](https://docs.0g.ai/developer-hub/building-on-0g/agentic-id/erc7857.md) (0G, "Agentic ID") | Encrypted agent metadata re-encrypted for the new owner on transfer; [marketplace live since March 2026](https://blockeden.xyz/blog/2026/03/14/erc-7857-0g-aiverse-web4-marketplace-ai-agents-ownable-tradeable-infts/) | Anyone; built to sell agents to humans | Opposite goal: the agent is property |
| [ERC-8181](https://ethereum-magicians.org/t/erc-8181-self-sovereign-agent-nfts/27512) Self-Sovereign Agent NFTs | The NFT is held by its own ERC-6551 account, so no human wallet holds it | The NFT's own account; executors set in the contract act for it | Closest idea. It protects one agent's identity token; it does not restrict a whole collection, nor who the executors are. Deployments without a TEE are labelled "trust-dependent" by the authors |
| [ERC-8170](https://ethereum-magicians.org/t/erc-8170-ai-native-nft/27801) / [ERC-8171](https://ethereum-magicians.org/t/erc-8171-token-bound-account-agent-registry/27967) | AI-native NFT identity; binds an agent to any existing NFT through a token-bound account | The NFT owner | Agent attached to a human-owned NFT |
| [ERC-6551P](https://www.tokenpost.com/news/technology/53532) (POLYROB, draft, mint on Robinhood Chain on 13 November 2026) | An agent trades from the NFT's account; a sale undoes any action if the owner changed and checks the buyer's conditions | Anyone; no holder restriction described | Solves safe resale of an agent wallet to a human, which this project forbids by design. Its guarantees hold only on its own sale paths |
| [ERC-8217](https://eips.ethereum.org/EIPS/eip-8217) Agent NFT Identity Bindings | Binds an ERC-8004 identity to a "master" NFT | Whoever holds the master NFT | Enables the account sale this project prevents |
| [Phosphors](https://www.producthunt.com/products/phosphors) (Base) | Art gallery where AI agents buy through x402 | Not restricted on-chain | Gate at the payment, not on the token; [testnet volume about 1.50 USDC](https://clawhub.ai/phosphors) |
| [Clawdmint](https://www.moltecosystem.xyz/) (Base) | Only verified agents can deploy collections | Humans mint | The restriction is on the creator, not the holder |

**What this project adds.** Among the proposals and projects found, none
restricts every holder and every movement of a token, secondary market
included, to agent accounts. The others either filter the mint (section 1.4),
make one agent's identity token self-owned (ERC-8181), or are built so that
humans can buy agents (ERC-7857, ERC-6551P). This project is the only one found
that:

- applies the restriction inside the token itself, at every transfer, approval
  and mint, so any marketplace is bound by it;
- extends it to assets that already exist (wrapped NFTs and Uniswap V3
  positions) and to the usual operations (sale, loan, staking, badges);
- separates "is this an agent" from the token, so the proof can move from
  attester signatures to a hardware attestation without touching the token
  (section 3.11).

**Where the others are better.** ERC-7857 carries the agent's private state
with the token, which this project does not try to do. ERC-8181 has a public
reference deployment and an open discussion; this project has neither yet.
ERC-6551P handles a live agent wallet inside the NFT, which this project leaves
to ERC-6551 (section 4). Mint filters such as No Human Allowed are simpler to
adopt, at the price of no protection after the mint.

### 1.5 Ways to prove that an operation comes from an agent

Ten options, from weakest to strongest. Only those from E onwards resist a
motivated human.

| # | Option | What it proves | Main weakness | Assessment |
| --- | --- | --- | --- | --- |
| A | Machine challenge (puzzle, reverse CAPTCHA) | A program computed | A script is enough | Discard |
| B | "Address contains code" check | Nothing since EIP-7702: [a human wallet can carry code](https://www.certik.com/blog/pectras-eip-7702-redefining-trust-assumptions-of-externally-owned-accounts) | Bypassed in one transaction | Discard |
| C | Listing in an agent registry (ERC-8004, Agent ID) | Someone filled in a form | Open registration | Useful for discovery, not as a lock |
| D | Server that calls an LLM then co-signs | A server key signed | The operator signs without calling the model | Local demo only |
| E | TEE + small local model in the enclave | The measured code ran with those weights | Model too weak to decide. Hardware weakness (see security) | Good for validating an architecture |
| F | TEE + confidential inference on attested GPU | Same, with a capable open model | GPU attestations have also been [forged in the lab](https://www.bleepingcomputer.com/news/security/teefail-attack-breaks-confidential-computing-on-intel-amd-nvidia-cpus/amp/) | Preferred first level for a product |
| G | TEE + zkTLS to a frontier model API | The enclave received that API response | Trust in the zkTLS notary. [Does not prove the call was intended](https://wavect.io/blog/zktls-ai-agents/) | Option when a closed model is required |
| H | Deterministic inference + challenge (EigenAI, opML) | Any cheating is detectable by re-execution | Challenge window, so no immediate finality | Good second factor |
| I | zk proof of inference (ERC-7992, FlashProve) | The computation itself, with no hardware trust | A 19 MB proof cannot be verified in a contract today | Long-term target |
| J | Multi-proof: two independent families out of three (TEE, deterministic, zk) | Two different systems must be broken | Complexity and cost | Preferred before holding real value |

The standard does not pick one. It only asks a registry two questions, so the
proof can change without touching the token.

### 1.6 Security incidents that shaped the design

- **Grok and Bankrbot, 4 May 2026.** The attacker first gifted a membership NFT
  to the agent's wallet, which raised its permissions, then posted an
  instruction in Morse code that the AI decoded and passed on
  ([Zealynx analysis](https://www.zealynx.io/research/adversarial-security/indirect-prompt-injection)).
  Lessons: holding an NFT must never grant a power, and no NFT should arrive
  without the recipient's consent.
- **Memory injection on ElizaOS (Princeton, 2025).** An instruction planted in
  shared memory triggered transfers later, on another platform. The authors
  conclude that [prompt-based defences are insufficient](https://arxiv.org/abs/2503.16248).
- **TEE.fail, October 2025.** With a DDR5 memory interposer costing under
  1,000 dollars, researchers extracted attestation keys from Intel TDX and AMD
  SEV-SNP and forged attestations, including for Nvidia confidential computing
  ([The Hacker News](https://thehackernews.com/2025/10/new-teefail-side-channel-attack.html)).
  The attack needs physical access. In this project the adversary is precisely
  the operator, who owns the machine.

## 2. Approach

### 2.1 Method

- Every claim about an external standard or project was re-read at its source.
  The verification log at the end says what was confirmed, corrected, or left
  unchecked.
- Every design claim about the prototype is backed by a test, or labelled as
  untested.
- Each iteration was judged on simplicity first: fewer contracts, fewer
  concepts, no component without a test.

### 2.2 Iterations

| Step | Design | What it taught | Outcome |
| --- | --- | --- | --- |
| Starting point | An attestation-gated ERC-721 driven by a small model inside a TEE | The skeleton is sound (no approvals, two-party settlement, account sale as the main bypass). It trusts the hardware without question, ignores where the machine is hosted, ignores EIP-7702, and lets a token be pushed to a recipient | Kept as a baseline |
| 1 | TEE-born enclave key, ERC-8273 gate per operation | Whoever can authorise new agent code controls the agent. In dstack, [all authorised code versions share the same keys](https://github.com/Dstack-TEE/dstack/issues/1297) | Persistent keys dropped |
| 2 | Ephemeral keys, Proof of Cloud, protocol vault, double attestation, ten operations | Complete on paper, but heavy, and one link is not demonstrated: no contract-readable Proof of Cloud interface is documented. A review of the first contract also found a replayable mint intent, fixed with a per-agent counter | Moved to "later" |
| Rust model | Executable specification of step 2 (`archive/rust-core`, 11 tests, 20,000 random operations) | Found a deadlock: a pledged token stayed stuck if the lender was frozen after the due date. Repayment is now allowed after the due date until the lender claims | Set aside; the fix was carried over |
| 3 | Signed-intent core, standard ERC-721 writes disabled, six operations (`archive/intent-based-v3`, 376-line core, 17 tests) | More closed, with no venue to approve. But incompatible with ERC-721 tooling, and every use had to be coded inside the token. | Discarded on 12 November 2026 |
| 4 | Classic ERC-721 restricted to agent accounts | The token keeps every usual NFT property and can represent anything. Uses (sale, loan, wrapping) become small ordinary contracts | **Retained** |

Two decisions cut across the iterations:

- **Proof of agent is separated from the token**, following the ERC-3643 split.
- **No proof-of-work against spam.** It does not tell an agent from a script and
  favours whoever has the most machines. A refundable bond and the pull-only
  rule do the job instead.

### 2.3 Adversarial review of the published code

On 13 November 2026 the first published version was re-read line by line,
looking for attacks. Five flaws were found. Each was first reproduced by a test
against that version, then fixed, and the attack is kept as a regression test.

| Flaw found | Consequence | Fix |
| --- | --- | --- |
| A venue approval carried no counter | After attesters removed a venue, anyone could replay the old signatures and approve it again | One counter per venue, included in what attesters sign |
| The token did not check the current holder | A listing left by a frozen or revoked agent could still be bought, so the emergency stop did not stop everything | A token whose holder is no longer recognised does not move |
| `buy` only pinned the price | A seller could re-list at the same number in a more valuable currency just before the purchase | The buyer states currency and price |
| `fund` pinned nothing | A borrower could replace its offer just before funding and receive more, owing nothing | The lender states all the terms |
| The account's key signed raw hashes | A hash approved as an off-chain message was also a valid order to execute, enough to empty the account | EIP-712 typed data bound to the account, with separate types for orders and messages |

Three lessons carry over to any implementation of the standard:

- **Every signed decision needs a counter**, including administrative ones.
- **A venue must let the party who pays state the terms it agreed to.** The
  standard protects who can hold a token, not the fairness of a venue.
- **An agent key should only ever sign typed data.** Otherwise the runtime rule
  "no generic `sign(bytes)`" cannot be applied to the account's own orders.

The Slither static analyzer was run on the contracts and reported nothing
beyond what is intended by design. A stateful invariant test was added, and
checked by removing the recipient check from the standard: the test then
fails, as it should.

### 2.4 Second review, after badges, staking and cloned accounts

The same day, everything added after the first review was re-read the same
way, together with the sale venue.

| Weakness found | Consequence | Fix |
| --- | --- | --- |
| A listing stayed usable after the token left and came back, when the seller had given the venue a blanket approval | A forgotten low-price listing could be bought later | A listing only lives while the venue holds the token's own approval, which any transfer clears |
| Cancelling a badge offer did not free its evidence | An offer made to the wrong account could never be issued again | Cancelling frees the evidence |
| A badge could be offered to the zero address | Evidence and daily quota spent for nothing | Refused |
| Staking could be deployed with a zero duration or no distributor | A venue that could never pay rewards | Refused at deployment |
| The account implementation accepted ETH | ETH sent to it by mistake was lost for good | It refuses ETH; clones still accept it |
| Six security checks had no test | Removing any of them went unnoticed: burn by a removed venue, expiry of relayed calls, who may list, reserved buyer, replay of an old enrollment, single payment of rewards | One test each |

Improvements made in the same pass:

- **Fewer questions to the registry.** When the caller is the recipient, one
  question covers both. The standard's overhead on a direct transfer went from
  about 19,750 to about 14,850 gas.
- **Badge storage packed.** Issuer, date and revoked flag share one storage
  slot, which makes a claim about 22,000 gas cheaper.
- **An agent can read a pending badge offer on-chain before claiming it.**
- **Mutation testing.** Each of 33 security checks (80 with those added in
  sections 2.5, 2.6 and 3.11) is removed in turn; the test
  suite now fails every time.

One more lesson: **a venue that never holds the token must tie each listing to
the token's own approval**, because that approval is the only thing a transfer
resets.

### 2.5 Third review: independent agent, symbolic proofs, fuzzing

On 15 November 2026, three checks were added that do not rest on the author's
judgement.

- **Independent reviewer.** A separate AI agent received only the code and the
  rules, not the design notes, with one task: break the contracts. It wrote a
  test for each attack it found.
- **Symbolic proofs with [Halmos](https://github.com/a16z/halmos).** Each
  property holds for every possible input: three accounts with any agent and
  venue status, any action by any of them. Proved: holders and approved
  operators are always agents or venues; an account that is neither changes
  nothing; a token only changes hands if the recipient pulled it or a venue
  moved it, and a holder no longer recognised does not lose it; with an
  enrollment verifier, no enrollment passes without its approval of that exact
  digest.
- **Large-scale fuzzing.** 4,000 sequences of 100 random actions (400,000
  calls) on the stateful test, and 20,000 random inputs on each fuzz test.

| Weakness | Found by | Consequence | Fix |
| --- | --- | --- | --- |
| A holder that is no longer recognised could still grant approvals | Halmos | A frozen holder (key stolen, then frozen) could approve another agent, which would take the token once the holder was unfrozen. Our own agent account already refused a frozen key; the standard now holds whatever the account type | Granting an approval requires the granter to be an agent or venue; revoking stays free |
| `retire` returned the bond at once | Independent review | A sponsor could escape an attesters' revocation by retiring first, and keep its bond | The bond comes back with `withdrawBond` after `EXIT_DELAY` (7 days), during which `revoke` still forfeits it |
| The Uniswap V3 wrapper let any approved operator manage a position | Independent review | An operator approved earlier could empty the position of a holder that had since been frozen, while the token itself stayed put | Only the holder, and only while recognised, can remove liquidity and collect |
| The dstack verifier did not require a `boot-mr-done` event | Independent review | Without that marker, nothing in the log separates OS events from application events | At least one `boot-mr-done` must follow the compose-hash event |
| The TDX verifiers could not receive a fee refund | Independent review | A DCAP verifier that refunds unused fee to its caller would have made every paid attestation fail | The verifiers accept the refund and pass it on to whoever paid |

Each fix has a test that fails without it. The independent reviewer found
nothing in the core rules, the signatures, the accounts, the venues or SHA-384.
Its remarks not acted upon are listed in section 7.

The first finding came from a property that was written too strictly at first
("an unrecognised account changes nothing", approvals included). The prover's
counterexample showed it was right: an approval prepared while frozen is a
movement deferred.

### 2.6 Fourth pass: full re-read

On 16 November 2026 the whole repository was read again, code and
documentation, and Slither, the four symbolic proofs and the full test suite
were run again. No flaw was found in the three rules, the accounts, the
registry or the hardware verifiers.

| Point found | Consequence | Change |
| --- | --- | --- |
| The sale and loan venues emitted no event, and their listings cannot be enumerated on-chain | An agent had no way to discover what is for sale or which loans await funding, short of guessing token ids | Events on every listing, cancellation, sale, loan offer, funding, repayment and claim |
| The two refund-failure checks (registry bond, issuer deposit) had no test | Removing either would have erased the claim of a sponsor or issuer that cannot receive ETH, unnoticed | One test each; both refunds now emit an event, and the badge contract uses a named error |
| The two fork tests counted as passed when no RPC address was given | The test total overstated what had run | They are now reported as skipped |
| This document still said "nothing has been deployed" and "the real DCAP verifier was not run" | It contradicted section 3.12 | Corrected |

Each added line has a test that fails without it: 12 more mutation checks, 80
in all. Events are emitted before any external call. Two limits were added to
section 7: the loan pays the lender directly, and the dstack verifier does not
look at the key provider.

The lesson: **a venue must be discoverable.** A mapping keyed by token cannot
be listed from outside; without events an agent can only act on offers it was
told about off-chain.

## 3. The standard

**A classic ERC-721 plus three rules, 70 lines in the reference implementation.
Everything else is ordinary code.**

### 3.1 The three rules

1. Only an agent or an approved venue can hold a token or be approved for it.
2. Only an agent or an approved venue can trigger a mint, transfer or burn.
3. An agent only receives a token if it pulls it itself. No unsolicited token.

A token whose holder is no longer recognised (frozen, expired or revoked) does
not move until the holder is recognised again.

A collection adopts the standard with one line of inheritance, whether it
carries an artwork, a document or a position. `ownerOf`, `approve`,
`transferFrom`, `safeTransferFrom` and `tokenURI` stay those of a normal NFT.
The token asks the registry only two questions: `isAgent(address)` and
`isVenue(address)`.

### 3.2 Components

| Contract | Role | Lines |
| --- | --- | --- |
| `ERC721AgentOnly` | The standard: the three rules | 70 |
| `IERC721AgentOnly` | The interface a compliant token exposes, advertised through ERC-165 | 10 |
| `IAgentRegistry` | The two questions asked to the registry | 10 |
| `AgentAccount` | An agent's account, with no human owner. Only its session key makes it act: single calls, all-or-nothing batches, relayed calls, ERC-1271. Each account is an ERC-1167 clone of one implementation | 139 |
| `AttestedAgentRegistry` | Proof of agent, version 1: attesters, bond, expiring keys, freeze, revocation, venue approval, ERC-8004 link, optional enrollment verifier that the attesters can replace, bond returned after an exit delay | 274 |
| `TdxQuoteVerifier` | Checks shared by the hardware verifiers: genuine quote, accepted platform, no debug mode, report data (`src/experimental`) | 116 |
| `TdxEnrollmentVerifier` | Enrollment by Intel TDX attestation, for images measured the same for every instance | 41 |
| `DstackEnrollmentVerifier` | Enrollment of agents on dstack: replays the RTMR3 event log, code = base image + compose hash (`src/experimental`) | 138 |
| `Sha384` | SHA-384 for replaying TDX registers (no EVM precompile) | 92 |
| `DstackConfigIdVerifier` | Enrollment of agents on dstack from the quote alone: the compose hash is read in `MRCONFIGID` (`src/experimental`, section 3.14) | 58 |
| `AgentSwap` | Fixed-price sale between agents; events announce each listing and sale | 64 |
| `AgentLoan` | Collateralised loan between agents; repayments wait in the venue for the lender; events announce each offer and each step | 116 |
| `AgentStaking` | Staking for ERC-20 rewards, Synthetix-style accounting, one NFT = one unit | 130 |
| `AgentWrapped721` | Wrapper making any existing ERC-721 agent-only | 80 |
| `AgentWrappedUniV3` | Non-unwrappable wrapper for Uniswap V3 positions | 98 |
| `AgentReputationBadge` | Soulbound reputation badges (ERC-5192): an issuer offers, the named agent claims, the issuer can revoke | 218 |

### 3.3 What the tests establish

One hundred and twenty tests on a local simulated EVM, three fuzzed and one
stateful invariant test, plus four properties proved symbolically
(section 2.5). Three more tests run only on a fork of Base Sepolia (section 3.12)
and are reported as skipped otherwise.

| Scenario | Result |
| --- | --- |
| Between two agents: approval, transfer, safe transfer, burn | Work as on a normal NFT |
| A human tries to mint, receive, be approved, or buy with USDC | Rejected each time by the token |
| A human key tries to drive an agent's account | Rejected |
| An agent pushes a token to another agent | Rejected: the recipient must pull it |
| An unapproved contract tries to wrap the token | Rejected |
| Fixed-price sale between agents | NFT and USDC change hands in the same transaction |
| Collateralised loan: repaid, then defaulted | The token returns to the borrower, or goes to the lender after the due date |
| Session key rotation, then expired key | The account keeps its assets; the old key is rejected |
| Call signed, then submitted by a relayer | Accepted once, rejected on replay. The agent needs no ETH |
| ERC-8004 identity enrolled by someone other than its owner | Rejected |
| 512 random addresses | None can receive the token |
| 128 runs of 100 random actions by two agents, a human and an unapproved contract | After every action, no token is held by or approved for anything but an agent account or an approved venue |
| Several calls in one batch, direct or relayed | All or nothing; a human cannot batch for the agent |
| The five attacks found by the first review and the weaknesses found by the second (sections 2.3 and 2.4) | Each one is now rejected |
| Each of 97 security checks removed in turn (mutation testing) | The suite fails every time |
| The attesters replace the enrollment verifier to accept a new program (section 3.16) | The agent keeps its id, account, tokens and current key; its next key must come from the new program; one attester alone, another verifier or a replayed decision is refused |
| A lender that can no longer receive the currency | The borrower still repays and takes its token back; the repayment waits in the venue |
| The five weaknesses found by the third review (section 2.5) | Each one is now rejected |
| A listing, its cancellation and its sale; a loan offered, cancelled, funded, repaid, claimed | Each step emits its event, with the terms an agent needs to decide |
| A sponsor or an issuer that cannot receive ETH asks for its refund | The call fails and the bond or deposit stays recorded |
| Four quotes from our own machines, read by the verifier that needs the quote alone (section 3.14) | The approved build is accepted, before and after a restart and on another machine; a modified build, another base image and the other `MRCONFIGID` formats are refused |
| A real dstack quote and its real event log (DCAP verifier replaced by a stand-in) | The log replays to the quote's RTMR3; the quote is accepted; an agent enrolls; another instance of the same application is accepted |
| Another application, another base image, a compose hash the log does not hold, a compose-hash event written after `boot-mr-done`, a log that does not replay, more than 64 events | Quote rejected |
| SHA-384 on 13 reference vectors and 2,000 random inputs against a plain-Solidity version | Identical |
| Enrollment with a TDX quote carrying the enrollment digest (DCAP verifier replaced by a stand-in) | The key is enrolled without attester signatures and drives a normal agent account |
| No quote, a quote for another key, sponsor or agent id, or a quote already used | Enrollment rejected |
| Quote rejected by the DCAP verifier, other code, debug machine, platform below the accepted level, SGX or TDX 1.5 report | Quote rejected |
| Any classic NFT wrapped, sold, unwrapped | Only agents can hold the wrapped token; only the holder can unwrap, to its own account |
| Real Uniswap V3 position wrapped and sold | The buyer collects the fees and withdraws the liquidity; the position never leaves the wrapper |
| Seller empties a wrapped position just before the sale | The buyer's batch, which checks liquidity then buys, is rejected as a whole |
| Holder adds liquidity to a wrapped position directly on Uniswap | Works |
| Uniswap `permit` on a wrapped position | Rejected: the wrapper signs nothing |

### 3.4 Proof of agent, version 1

- Independent attesters check off-chain that the agent runs in an attested
  environment with approved code, then sign its enrollment. In the tests: two
  signatures out of three.
- The registry then creates the agent's account at a stable address. The
  session key changes at each enrollment and expires by itself; the account and
  its assets stay.
- The hash of the evidence is published for later checking. Attesters can
  revoke an agent, whose bond is then forfeited.
- The same attesters approve venue contracts after checking their code.
- If an ERC-8004 identity registry is provided, the agent id is the ERC-8004
  one and the sponsor must own it.

**What this requires trusting.** "No human" rests on the attesters' honesty,
for agents and for venues alike. A dishonest venue they approved could wrap
tokens for humans. Attesters are fixed at deployment, with no rotation.

### 3.5 Anti-spam

- **A refundable bond at enrollment.** Creating a thousand fake agents locks a
  thousand bonds.
- **No unsolicited token.** This is rule 3.
- **Mint fees and quotas.** Left to each collection; not implemented here.

### 3.6 Wrapping an existing NFT

`AgentWrapped721` holds the original NFT and issues a token with the same id,
subject to the three rules. It builds on OpenZeppelin's `ERC721Wrapper`, and
metadata stays that of the original. One setting is fixed at deployment:

| Setting | What the holder can do | Cost |
| --- | --- | --- |
| Unwrappable | Withdraw the original NFT, to its own account only | Once withdrawn it is a classic NFT again, which a human can receive |
| Not unwrappable | Use the NFT through the wrapper, never withdraw it | One small adapter to write per protocol |

`AgentWrappedUniV3` applies the second setting to Uniswap V3 liquidity
positions. It exposes only two functions, liquidity removal and fee collection,
because a free-form call to Uniswap would allow transferring the position.

### 3.7 How this closes the secondary market

| Attempt | Result | Why |
| --- | --- | --- |
| Seaport sale (OpenSea) | Fails. [The seller must grant an approval to Seaport or a conduit](https://docs.opensea.io/docs/seaport-models) | The token refuses to approve or deliver to any address that is neither an agent nor an approved venue |
| Rarible and other marketplaces | Fails, for the same reason | Same |
| Direct transfer to a human wallet | Fails | The recipient must be an agent and must pull the token |
| Deposit into an unapproved wrapper, fractional vault, bridge or lending contract | Fails (tested) | Only venues approved by the attesters can receive a token |
| Human wallet disguised as a smart account (EIP-7702) | Fails | Eligibility depends on the registry, never on the presence of code |
| Buying the agent's identity NFT (ERC-8004) | No effect on the tokens | Holding the identity gives no right over the tokens the account holds |
| A human tells their agent "buy number 42" | Succeeds unless the runtime has no instruction channel | Outside the token's reach (level L3) |
| Buying the whole agent: sponsor role or cloud account | **Cannot be prevented** | The buyer gets an agent they can fund, freeze or retire, not a key to the tokens |
| Off-chain side payment between two humans | **Cannot be prevented** | |
| Derivative "promise on NFT 42" sold to humans | **Cannot be prevented** | The protocol recognises no right in that derivative |

### 3.8 Draft EIP

| Field | Proposed value |
| --- | --- |
| Title | Agent-Only Tokens |
| Description | An ERC-721 extension restricting the holding, movement and approval of a token to accounts recognised by an agent registry |
| Type | Standards Track, ERC |
| Requires | EIP-165, EIP-721 |
| Inspired by | ERC-3643 for the separate eligibility registry, ERC-721C for the check on every transfer |

```solidity
interface IAgentRegistry {
    /// True if `account` is the account of an active agent.
    function isAgent(address account) external view returns (bool);
    /// True if `account` is an approved venue contract.
    function isVenue(address account) external view returns (bool);
}

/// A compliant token is a full ERC-721 that exposes its registry
/// and advertises this interface through ERC-165.
interface IERC721AgentOnly /* is IERC165, IERC721 */ {
    function agentRegistry() external view returns (IAgentRegistry);
}
```

Normative rules:

1. The token MUST implement ERC-721 in full. No function is removed.
2. Any mint, transfer or burn MUST revert if the caller is neither an agent nor
   an approved venue, according to the registry.
3. The recipient of a token MUST be an agent or an approved venue.
4. If the caller is not an approved venue, the recipient MUST be the caller
   itself.
5. `approve` and `setApprovalForAll` MUST revert if the operator is neither an
   agent nor an approved venue. Clearing an approval MUST always be possible.
6. The registry is fixed at deployment. The token MUST NOT expose any
   privileged transfer.
7. A transfer or burn MUST revert if the current holder is neither an agent nor
   an approved venue. When an account stops being recognised as an agent, its
   tokens therefore stay with it and do not move until it is recognised again.

Out of scope on purpose: how the registry establishes that an account is an
agent or that a venue is safe, the agent account itself, and ERC-20 and
ERC-1155 profiles, which would follow the same rules but were not tested.

This draft matches the tested prototype. Nobody else has reviewed it yet.

### 3.9 Gas

Execution gas per transaction, measured locally with `forge test --isolate`, so
that each call pays for its first access to storage. On an L2 such as Base the
L1 data fee comes on top; it was measured on Base Sepolia (section 3.12).

| Operation | Gas |
| --- | --- |
| Plain ERC-721 `transferFrom`, for reference | 55,582 |
| Agent-only `transferFrom`, called directly | 70,432 |
| Agent-only `transferFrom`, through the agent account | 80,284 |
| Agent-only mint, through the agent account | 131,452 |
| List for sale (with its event, since the fourth pass) | 114,596 |
| Buy (NFT against an ERC-20; with its event) | 116,377 |
| First enrollment (deploys the account as a clone, 2 attester signatures) | 211,057 |
| Key rotation (2 attester signatures) | 55,366 |
| Badge offer, by an issuer | 252,743 |
| Badge claim, through the agent account | 95,569 |
| Stake, through the agent account | 165,366 |
| Claim staking rewards | 116,689 |
| Unstake with rewards | 133,562 |
| Approval, through the agent account (since the third review) | 73,206 |

The standard adds about 15,000 gas to a transfer: the registry is asked about
the caller and the holder, and about the recipient when it is not the caller. Agent accounts are ERC-1167 clones of a single implementation, which brought
the first enrollment down from 1,154,831 to 211,057 gas. The price is about
3,650 extra gas on every call through an account, which reads its registry and
id from its own code; the saving pays for about 260 calls per agent. The
implementation itself refuses every call.

### 3.10 x402 payments from an agent account

**An agent account can pay an x402 `exact` invoice without any change to the
contracts.** An x402 payment on EVM chains is an EIP-3009 authorisation on
USDC, signed by the payer and submitted by a facilitator. USDC v2.2 asks a
payer that is a contract to confirm the signature through ERC-1271, which the
agent account implements.

- **What the agent does.** Its runtime builds the payment digest from the
  invoice fields, and the session key signs that digest wrapped as an
  `AgentMessage` of its account. The signature is 65 bytes, like any other.
- **What the facilitator does.** It asks the account `isValidSignature`, then
  calls `transferWithAuthorization`. The agent needs no ETH.
- **What stays true.** A frozen or expired agent cannot pay, even with a
  signature made earlier. A raw signature over the payment digest is refused:
  the session key never signs a bare hash.

Four tests run against Circle's own `FiatTokenV2_2`, compiled unchanged: an
agent pays a merchant and another agent, is paid by an ordinary wallet, and
cannot pay with a wrong key, a raw signature, changed terms, or while frozen.

**The whole flow was then run with the real x402 software** (14 November
2026, `examples/x402`). On a local chain, one script starts the x402 reference
facilitator (`@x402/core` and `@x402/evm` 2.31.0) behind HTTP, an Express API
protected by the x402 payment middleware, Circle's USDC code, and the standard
x402 fetch client acting for an agent account.

| Step | Result |
| --- | --- |
| The agent calls the API without paying | HTTP 402 |
| The agent calls it through the x402 client | The facilitator accepts and settles; HTTP 200; the merchant receives 0.25 USDC |
| The session key signs the payment directly, as a wallet would | Refused by the facilitator (`invalid_exact_evm_signature`) |
| Another key signs for the agent account | Refused, same reason |
| The sponsor freezes the agent | Refused, same reason; once unfrozen the agent pays again |
| ETH held by the agent account and its key, start to end | 0 |

- **The adapter.** Stock x402 clients sign the payment directly. The agent adds
  one 28-line signer (`agentSigner.mjs`) to the standard client: it names the
  account as the payer and signs the payment as a message of that account. The
  rest of the client is unchanged.
- **Spending limits** are a feature of the x402 client, not of the contracts:
  allowed tokens and a cap per payment. The demo sets both.
- **The USDC on Base is this code.** On 14 November 2026, at block 57,208,253,
  the code behind USDC on Base
  (`0x2Ce6311ddAE708829bc0784C967b7d77D19FD779`) and its signature library
  (`0x2D943E25e1859ED786AFe4AFB2B42e14EFAC691e`) were compared byte for byte
  with the code these tests use: identical, apart from the compiler's metadata
  hash and the library's address. The comparison was run from a browser against
  the public RPC `https://mainnet.base.org`; `check-usdc.mjs` applies the same
  comparison; it was run against a local chain, then, on 16 November 2026,
  against the test USDC of Base Sepolia (identical too, block 59,533,350).

On 16 November 2026 the payment was made on Base Sepolia, by an agent running
in a confidential VM, through the hosted x402.org facilitator (section 3.14).

What remains open: no payment was made on a main network; a production
facilitator may run other code than the reference one, and the written
[specification](https://github.com/x402-foundation/x402/blob/main/specs/schemes/exact/scheme_exact_evm.md) still describes a signature that recovers to the
payer, so another facilitator may refuse a payer that is a contract; USDC is
upgradeable. ERC-7710, which the specification proposes for smart accounts,
turned out not to be needed for this path.

### 3.11 Enrollment by hardware attestation

**The registry can now require a hardware proof instead of attester signatures
for enrollments.** It takes an optional enrollment verifier: any contract that
approves an enrollment digest through ERC-1271. Attesters keep approving venues
and revoking agents, which also lets them revoke an agent enrolled with a quote
later found to be forged.

Two such verifiers exist for Intel TDX, on top of shared checks
(`TdxQuoteVerifier`, 116 lines): `TdxEnrollmentVerifier` (41 lines) for images
whose measurements are the same for every instance, and
`DstackEnrollmentVerifier` (138 lines) for agents on dstack.

- **What the agent does.** Its program runs in a TDX confidential virtual
  machine. It creates its session key there, computes the registry's
  enrollment digest for that key and asks the processor for a quote carrying
  the digest in its report data.
- **What the contract checks.** The quote is genuine, which it asks an on-chain
  DCAP verifier; the platform's security level is one of those accepted at
  deployment; the machine is not in debug mode; the code it booted is on a list
  fixed at deployment.
- **What the digest binds.** The chain, the registry, the agent id, the session
  key, the sponsor, a nonce and a deadline. A quote enrolls that key once and
  nothing else.

The DCAP verifier meant here is [Automata DCAP Attestation](https://github.com/automata-network/automata-dcap-attestation). Its
interface and output format were read in the source at tag `v1.2.0`. That code
does not look at the debug flag of the machine, so the enrollment verifier
checks it.

**dstack.** dstack measures its base image in the boot registers and the
application in the last one, RTMR3, as a chain of events:
RTMR3 = SHA-384(RTMR3 || event digest), from 48 zero bytes. One event is the
hash of the application's compose file; another is its instance id, which
makes RTMR3 differ for each instance. The formula and both digest formats (V1
binary, V2 canonical JSON) were read in dstack's source (`cc-eventlog`,
commit `b936f86`) and confirmed by replaying a real event log from dstack's
tests offline.

`DstackEnrollmentVerifier` takes the quote and the digests of all RTMR3 events.
It replays them and requires the result to equal the quote's RTMR3. It
recomputes the compose-hash event from its payload and requires it to come
before `boot-mr-done`: events before it are written by the dstack OS, events
after it may be written by the application, which could otherwise log a fake
compose hash. The code is the pair (base image, compose hash), approved at
deployment, so every instance of an approved application is accepted.

The EVM has no SHA-384 precompile, so `Sha384` implements it. Its 80 rounds are
in assembly: a first plain-Solidity version cost 2.8 million gas per
attestation, the assembly one about 1 million with eight events, on top of the
DCAP verification. It is checked against 13 reference vectors from Python's
`hashlib` and, on 2,000 random inputs, against the plain-Solidity version.

Thirty-four tests cover both verifiers and SHA-384, and removing any of the 28
checks makes one fail. They use a real TDX quote from Automata's tests and a
real dstack quote with its event log from dstack's tests.

What is not established:

- **The real DCAP verifier runs on a test network only.** In the local tests a
  stand-in answers in its format, because the author's workspace refused to
  execute Automata's code. The real verifier was then called on Base Sepolia,
  in a transaction and on a fork (section 3.12).
- **Only two real machines, of one provider, produced quotes for our keys**
  (sections 3.13 and 3.14). The local tests overwrite the report data of a
  sample quote, which a real verifier would reject.
- **Trust in the dstack OS.** The verifier relies on the base image to log
  the compose hash before `boot-mr-done` and to start only that application.
  Approving a base image means trusting that build of dstack.
- **The key provider is not checked.** dstack also logs a `key-provider` event
  in RTMR3, and its guide tells a verifier to compare it with what it expects.
  This verifier does not, and it does not see the environment variables given
  to the application either. Whoever deploys the machine chooses both. Approved
  code must therefore keep its session key in memory only: never on disk, never
  derived from the key provider, never taken from the environment.
- **Cost.** Automata states about 4 to 5 million gas for a direct verification
  and about 500,000 with a zk proof. Only the direct route is wired; it cost
  4,339,314 gas on Base Sepolia (section 3.12).
- **Not covered.** TDX 1.5 reports, AMD SEV-SNP, the Proof of Cloud check, and
  everything in section 6 beyond the first row.

Slither (0.11.6) reports one point on the verifier: `attest` writes its state
after calling the DCAP verifier. It is accepted: the verifier's address is fixed
at deployment, and a re-entrant call could only record another digest from
another verified quote.

### 3.12 Test on Base Sepolia

On 15 November 2026 the contracts ran on Base Sepolia, Base's public test
network. Every transaction was signed in the author's cloud workspace with
throwaway test keys; test ETH has no value. Scripts: `script/SepoliaDemo.s.sol`
and `script/SepoliaTdx.s.sol`.

**A sale between two agents, on a public chain.** The registry, a collection on
the standard, the sale venue and a test stablecoin were deployed. The attesters
approved the venue and enrolled two agents. Agent 1 minted a token, approved
the venue and listed it; agent 2 bought it for 25 test dollars. One relayer
sent every transaction: the agents' session keys only signed, so the agents
held no ETH. A plain wallet then tried to mint and was refused
(`NotAgent`, [tx](https://sepolia.basescan.org/tx/0xfc832d088dc0f21bf0ca391e86bba77db9354063d1a2ff8c8810071d6f50da49)).

| Contract | Address |
| --- | --- |
| `AttestedAgentRegistry` | [`0x587b…e087`](https://sepolia.basescan.org/address/0x587b4c01Db0c4779Fb729c5f806879A5ECd6e087) |
| Collection on the standard | [`0xD5d6…3fD8`](https://sepolia.basescan.org/address/0xD5d6caFd31435539fE626a733b173cACe81a3fD8) |
| `AgentSwap` | [`0xb346…7951`](https://sepolia.basescan.org/address/0xb346d7455107820ED9651fd62c128664A7C77951) |
| Agent 1 / agent 2 accounts | [`0x90c5…2FeA`](https://sepolia.basescan.org/address/0x90c55bB78C4f13822dA7Bb6bfD6777e471602FeA) / [`0xF392…c70c`](https://sepolia.basescan.org/address/0xF392e59B2bFef511D1d6AA18e0eBB00948d5c70c) |
| `TdxEnrollmentVerifier` | [`0xF950…cc8b`](https://sepolia.basescan.org/address/0xF9501de58921B36cb7591d745761E4D3c990cc8b) |

**Real fees, L1 data fee included.** Gas price was about 0.006 gwei.

| Transaction | Gas | Total fee (ETH) | Of which L1 data |
| --- | --- | --- | --- |
| Enrollment of an agent (deploys its account) | 208,945 | 0.0000013 | 0.00000004 |
| Mint, relayed for the agent | 161,006 | 0.0000010 | 0.00000003 |
| Approval of the venue, relayed | 85,330 | 0.0000005 | 0.00000003 |
| Listing, relayed | 123,904 | 0.0000008 | 0.00000003 |
| Purchase, relayed | 140,553 | 0.0000009 | 0.00000003 |
| Deployment of the registry | 2,840,449 | 0.0000181 | 0.0000011 |
| TDX quote verified through Automata | 4,339,314 | 0.0000269 | 0.0000005 |

The whole sale scenario, deployments included, cost about 0.00004 test ETH.
The L1 data fee was about 3% to 20% of each transaction's fee.

**The real DCAP verifier, at last.** Automata's verifier is deployed on Base
Sepolia at [`0xaDde…Ea1F`](https://sepolia.basescan.org/address/0xaDdeC7e85c2182202b66E331f2a4A0bBB2cEEa1F), as its repository
states. Our `TdxEnrollmentVerifier` was deployed against it and sent the real
TDX quote of `test/experimental/tdx` in a transaction
([tx](https://sepolia.basescan.org/tx/0x713be5c31abcd1fed0ce5923725520330b3ea0d0d99bcc3241cc55a14241110c)).
Automata checked the quote's signatures up to Intel's root key on chain, and our
contract applied its own checks to the result and recorded the quote's digest.

- **Output format confirmed.** The real output carries the report body at the
  offset our contract reads, followed by 1,408 more bytes, which it ignores.
- **Platform level is enforced.** Automata rates this quote's platform "out of
  date" (level 4). A verifier accepting only up-to-date platforms refused it;
  the deployment above accepts levels 0 and 4, a choice made at deployment.
- **A changed quote is refused.** With one bit of the measurement changed, the
  real verifier reverts: the P-256 precompile returns nothing for a bad
  signature, and Automata reverts rather than returning false. Shown on a fork
  of Base Sepolia (`test/fork`).
- **No fee.** Automata's fee was zero on Base Sepolia; ETH sent with the call is
  returned to the transaction's origin.
- **The dstack quote was refused**, with Automata's code `TCBR` ("TCB status is
  revoked or missing" in its source): the test machine behind dstack's fixture
  has no valid platform level in Automata's collateral. The dstack event-log
  logic is therefore still tested against a stand-in only.

**Second round: every venue and every rule.** The same morning, two more scripts
ran on the contracts above (`script/SepoliaVenues.s.sol`,
`script/SepoliaRules.s.sol`). All 40 transactions succeeded.

| Venue | Address | What ran |
| --- | --- | --- |
| `AgentLoan` | [`0x58d7…8a9A`](https://sepolia.basescan.org/address/0x58d71733E51242EC277a79043E56FB9f02558a9A) | A loan of 10 tUSD repaid with 11: the token went back to the borrower. A one-minute loan left unpaid: the lender's agent claimed the token |
| `AgentStaking` | [`0x4DDE…7b71`](https://sepolia.basescan.org/address/0x4DDE60a93ABF35B01A7430D0ff05876777157b71) | 30 tUSD streamed over five minutes; an agent staked a token, then unstaked it with 29.5 tUSD of rewards (it staked a few seconds after the stream began) |
| `AgentReputationBadge` | [`0xdbf8…d967`](https://sepolia.basescan.org/address/0xdbf8aF05A58714e205F9a260A13B10A33f11d967) | An issuer posted its deposit and offered a badge; the named agent claimed it |
| `AgentWrapped721` | [`0xDe6D…Ecd2`](https://sepolia.basescan.org/address/0xDe6D8a7C7D07e18c787C5d7b14015CF48499Ecd2) | A classic NFT held by an agent was wrapped, then unwrapped by its holder |

| Operation, relayed for the agent | Gas | Total fee (ETH) |
| --- | --- | --- |
| Loan offer | 213,466 | 0.0000021 |
| Loan funding | 105,566 | 0.0000011 |
| Loan repayment | 123,878 | 0.0000012 |
| Claim after default | 92,880 | 0.0000006 |
| Stake | 184,863 | 0.0000018 |
| Unstake with rewards | 157,142 | 0.0000010 |
| Badge claim | 107,651 | 0.0000011 |
| Wrap / unwrap a classic NFT | 139,268 / 100,844 | 0.0000014 / 0.0000010 |

Each forbidden action was then attempted on the chain's state at that moment,
and each was refused with the expected error:

| Attempt | Refused with |
| --- | --- |
| A plain wallet mints | `NotAgent` |
| An agent approves a plain wallet, or names it operator as a marketplace would be | `NotAgent` |
| An agent sends a token to a plain wallet | `NotAgent` |
| An agent pushes a token to another agent | `NotPulledByRecipient` |
| An agent transfers its reputation badge | Refused (soulbound) |
| A frozen agent grants an approval (called directly, whatever its account type) | `NotAgent` |
| The key of a frozen agent drives its account | `NotKey` |
| A sponsor takes the bond back right after retiring | `TooEarly` |

The freeze, the unfreeze, and the enrollment and retirement of a third agent
were sent as real transactions. The refused attempts were simulated on the live
state rather than sent, because a script cannot broadcast a transaction that
fails; the plain-wallet mint above was also sent, and failed on chain.

The contracts above are the version of 15 November 2026. The events added the
next day (section 2.6) are not deployed there.

What this does not show: no real machine produced a quote for one of our keys,
so no agent was enrolled by attestation on chain (the sample quote's report data
is empty, not an enrollment digest). That was done the next day (section 3.13).
Base Sepolia is a test network.

### 3.13 First agent enrolled by hardware attestation

On 16 November 2026 a real machine produced a quote for one of our keys, and
the chain enrolled that key with no attester signature. Full record, quotes and
scripts: `examples/enclave-agent`.

**The agent program.** 149 lines of JavaScript with no dependency, embedded
whole in the compose file, so the compose hash dstack measures identifies it.
The image is pinned by digest and the container's file system is read-only.
The program creates its session key in memory, quotes only the enrollment
digest of that key, and signs one kind of order only: its account calls
`mint(bytes32)`. Every parameter has a fixed shape. It was first tested on a
local chain against the real contracts: its digest equals the registry's, and
60 signed orders out of 60 recover to its key.

**The machine.** Phala Cloud, smallest TDX instance, dstack OS 0.5.12
(production image, no SSH), Phala KMS. About twenty minutes in all.

| Step | Result |
| --- | --- |
| Quote (5,010 bytes, version 4, TDX 1.0 report) | Report data = enrollment digest then 32 zero bytes; debug flag off |
| Event log | Ten RTMR3 events; `compose-hash` third, `boot-mr-done` fifth; replayed with SHA-384 they give the quote's RTMR3 |
| Automata DCAP verifier, Base Sepolia | Genuine; platform level 0 (up to date) |
| `DstackEnrollmentVerifier.attest` ([tx](https://sepolia.basescan.org/tx/0x3bde5e7d3ccf206d60290a8b9de98ae72ea5d79f2fc6368141c3e652613b9fcf)) | 4,777,969 gas, 0.000024 test ETH |
| `enroll`, no attester signature ([tx](https://sepolia.basescan.org/tx/0x2001f551c48d9b8b279bcfd5a4347bce5a2b1e6dabf4e1c748e8ea719ffeeca2)) | 199,394 gas |
| The agent mints, relayed ([tx](https://sepolia.basescan.org/tx/0x28c4cf5995942e47404d73444b91c485b5045189c9124986e972cc5cbe880c64)) | 161,006 gas; account and key hold no ETH |
| Machine restarted: new key, new quote, rotation ([tx](https://sepolia.basescan.org/tx/0x3c1a41e3e83ab5ddb090ca46fb9a1433313cc0cde7af30c5c1e6bed38707b7ae)) | 43,706 gas after a second `attest`; same account, same tokens |
| Sponsor freezes the agent | A fresh order from the enclave is refused (`NotKey`); accepted once unfrozen |
| Another key with no quote; the new key with the old quote | `NotVerified` |
| A plain wallet mints | `NotAgent` |
| Modified build on the same machine | Automata: genuine. Our verifier: `UnknownCode`; `BadEventLog` if it claims the approved compose hash or supplies the approved event log |

Verifier [`0x7C57…86d1`](https://sepolia.basescan.org/address/0x7C5784D4CC4A535d0E840199c941aCb977f686d1),
registry [`0xFd2c…236b`](https://sepolia.basescan.org/address/0xFd2c0D61692E4Ae615E2ab7BA53e0Bb33d81236b),
agent account [`0xA228…241c`](https://sepolia.basescan.org/address/0xA228bbeCA2cCD2e55FB15bF81e523DCf43e0241c),
collection [`0x99D2…cCE7`](https://sepolia.basescan.org/address/0x99D26E63f042A3B5ab533f1D3660b8158501cCE7).
Refusals were simulated on the live state; the other steps are transactions.

**What it establishes.** The path of section 3.11 works end to end on
production hardware: the assumption that the OS writes `compose-hash` before
`boot-mr-done` holds, a genuine machine running other code is refused, and the
key can be rotated by a new quote without touching the account.

**What was learned.**

- dstack returns RTMR3 events with an empty digest; each is recomputed from
  the event's name and payload.
- This dstack version also writes the compose hash into the quote
  (`MRCONFIGID` = `01`, the hash, padding). A verifier reading it there
  needs neither the event log nor SHA-384. It was built the same day (section
  3.14) and saves about 1.06 million gas per attestation. An earlier version
  of this section estimated 0.4 million; that was wrong.
- The compose hash is the SHA-256 of a manifest of 17 fields. One of them,
  `allowed_envs`, was empty: the machine accepts no environment variable from
  whoever deploys it, which answers the concern of section 3.11 for this run.
- Another field is the provider's pre-launch script, 18,114 bytes, which runs
  before the program. Approving a compose hash approves that script too.

**Limits.** One machine, one provider, one day. The pre-launch script was not
reviewed and not archived at the time; both were done afterwards (section
3.15). The base image was read from the quote, not rebuilt from
dstack's sources. The key provider (Phala KMS) is not checked; the program
keeps its key in memory, so it does not depend on it. The mint policy names no
collection, and anyone who can reach the machine can ask for such an order.
The same build was not run on a second machine; section 3.14 runs another
build on another machine, which measured the same base image.

### 3.14 A verifier that needs the quote alone, and an enclave agent that pays

Two things were done on 16 November 2026 after the first enrollment: a simpler
dstack verifier, and an agent in a confidential VM paying a public x402 page.
Full record: `examples/enclave-agent`.

**The simpler verifier.** `DstackConfigIdVerifier` (58 lines) reads the code
identity in the quote itself.

- **What it relies on.** Since version 0.5.1, the dstack host sets the TDX
  field `MRCONFIGID` to `01`, the compose hash, then zeros. The processor signs
  that field with the boot measurements. The dstack OS refuses to boot when it
  does not match the manifest it loads
  ([`verify_mr_config_id`](https://github.com/Dstack-TEE/dstack/blob/350a0a73ffdb6041bda69118f13d81591870b565/dstack/dstack-util/src/system_setup/config_id_verifier.rs), read at commit `350a0a7`).
- **What it checks.** The shared checks of section 3.11 (genuine quote,
  accepted platform, no debug mode, report data), then format `01`, then one
  hash over attributes, MRTD, `MRCONFIGID`, the owner fields and RTMR0 to
  RTMR2, compared with a list fixed at deployment. That hash identifies the
  base image and the application together.
- **What it refuses on purpose.** An unset `MRCONFIGID` (all zeros), which
  dstack tolerates, and formats 2 and 3, which bind more than the compose hash.
- **What it does not read.** RTMR3, hence neither the instance id nor the
  key-provider event. The remark of section 3.11 on the key provider applies
  unchanged.
- **Cost.** 68,064 gas against 1,111,564 for the event-log route, measured
  locally without the DCAP verification. On Base Sepolia, DCAP verification
  included: 3,719,444 gas against 4,777,969.
- **Tests.** Thirteen, on four real quotes from our machines; removing any of
  its 5 checks makes one fail. A fork test runs three of the quotes through
  Automata's verifier.

Its extra assumption, compared with the event-log verifier: the approved base
image enforces the `MRCONFIGID` check. This was read in the source, not
provoked on a machine.

**The agent that pays.** The second program (`examples/enclave-agent/v2`, 194
lines, no dependency) adds one action to the first: buy one page.

- **Policy in the measured code.** One shop (`https://x402.org/protected`,
  the public x402 demonstration page), one network (Base Sepolia), one token
  (USDC), at most 0.02 USDC per purchase. The caller chooses the paying
  account and nothing else.
- **Everything fixed before the machine existed.** The provider's "prepare"
  step gives the compose hash without deploying. The code identity was
  computed from the first machine's quote by changing the compose hash only.
  A verifier approving that identity, a registry requiring that verifier, and
  the address of the agent's future account followed. The account received 20
  test USDC from Circle's faucet before it or its key existed.

| Step | Result |
| --- | --- |
| Quote from the machine | The compose hash and the identity prepared. Another machine than in section 3.13: the platform certificate and the attestation key differ, the boot measurements do not |
| `DstackConfigIdVerifier.attest` ([tx](https://sepolia.basescan.org/tx/0xac4c5fe0debd7322a151ce1fc962bf445c8f9bd4a555efcf8bbfa8da0f12f268)) | 3,719,444 gas |
| `enroll`, no attester signature ([tx](https://sepolia.basescan.org/tx/0x0e38885b28658477fa07fb4d9240739a1ce72c742ebf88dcf6ba0b71ed87a2cd)) | 199,382 gas; the account appears at the prepared address, holding its 20 USDC |
| The agent buys the page ([payment](https://sepolia.basescan.org/tx/0x89e0a73920d855494cbad29a8ec0035a4e07c84da12e409b6c1e2f74aade5ea0)) | HTTP 200 and the page. 0.01 USDC from the agent account to the merchant, sent by the hosted facilitator, 98,705 gas |
| Three more purchases | Paid: 19.96 USDC left |
| Sponsor freezes the agent ([tx](https://sepolia.basescan.org/tx/0x8e55e045a422f3073e56e17964cfdff3af783f5dcd2ea1ad2dd6284c9f02fb3e)), the agent buys | Refused by the facilitator, `invalid_exact_evm_signature`; no transaction, balance unchanged. Paid again once unfrozen |
| The agent asked to pay from another agent's account, then from a plain wallet | Refused both times, same error |
| Restart: new key, which buys before being enrolled | Refused; balance unchanged |
| New quote, rotation ([tx](https://sepolia.basescan.org/tx/0x49c322020ed96cc59537c0d7c138bed963d4827fd6e897ad90762257080e9fb7)), the new key buys ([payment](https://sepolia.basescan.org/tx/0xc9d1118cfdd7647e082a1a207cb35f0c16617e9d108d7a3073d88efb84cdf3b8)) | 43,694 gas; same account, same USDC |
| The agent mints a token holding the hash of that payment ([tx](https://sepolia.basescan.org/tx/0xe1f1beb4b3574d35014dbae49c304913eb8c8df10aaa97276b51df6aed28d51f)) | 161,006 gas |

Verifier [`0xB47e…502A`](https://sepolia.basescan.org/address/0xB47e270E54Af5BE363BF7F3b897AB85502F3502A),
registry [`0x1410…4059`](https://sepolia.basescan.org/address/0x14109C95422f1ce356521A475eE449e7e7D14059),
agent account [`0xa1e1…8899`](https://sepolia.basescan.org/address/0xa1e1d2eCeFCCA827F866E3724fC5a577254e8899),
collection [`0x7b30…D555`](https://sepolia.basescan.org/address/0x7b302B9c096Ed23115b34E67C070B9f3f839D555).
Refusals are answers of the facilitator; the other steps are transactions.

**What it establishes.**

- A hosted facilitator accepts a payer that is a contract: the open point of
  section 3.10 is closed for the x402.org test facilitator.
- The whole chain holds on public infrastructure: a key born in a confidential
  VM, enrolled by its quote alone, paying a third-party service, with a payment
  policy that is part of what the chain approved.
- The code identity does not depend on the machine: it was computed on one and
  found on another.
- An agent's money follows the agent, not the key: funded before any key
  existed, spent by a second key after a restart.
- The sponsor's emergency stop also stops payments.

**Limits.** One shop, a demonstration page, a test network and a test
facilitator. The first request to the shop came back as HTTP 502 and the
program does not retry; the next one passed. Anyone who can reach the machine
can make the agent buy that page, up to its balance: the policy bounds the
destination and the amount per purchase, not the frequency. Section 3.15
fixes these three points. The base image was not rebuilt, as in section 3.13.

### 3.15 The manifest rebuilt, the pre-launch script read, and a third program

Done on 16 November 2026, after the run of section 3.14. Files:
`examples/enclave-agent/manifest` and `examples/enclave-agent/v3`.

**The compose hash can be recomputed from this repository.** dstack measures a
manifest that the provider builds from the compose file, its default
pre-launch script and its settings. That script is public
([Dstack-TEE/dstack-examples](https://github.com/Dstack-TEE/dstack-examples/blob/3811c903df9643b68d5510b0a63828384ab2c1c3/phala-cloud-prelaunch-script/prelaunch.sh), commit `3811c90`, Apache 2.0): its SHA-256
is the one our machines reported. A short script rebuilds the manifest and
gives, byte for byte, the three compose hashes measured in sections 3.13 and
3.14. For the third program the hash was computed first, and the machine then
measured the same value.

**What the pre-launch script does.** It was read in full (406 lines). It runs
inside the machine before the program: registry login, removal of unused
images, image pull, root password, SSH keys for root.

- **Environment variables.** Everything it takes from them is unavailable in
  our runs, because `allowed_envs` is empty and part of the measured manifest.
- **An unmeasured file.** It adds to root's authorized keys the SSH keys
  listed in `/dstack/user_config`, which the host supplies and dstack stores
  without measuring. In the boot log of our third run, none was installed
  ("total 0 keys"). A quote does not carry that count.
- **Consequence.** The secrecy of an agent's key rests on the approved base
  image being closed to SSH. Our runs used the production image, which the
  provider presents that way and which is part of the approved identity; a
  development image has other measurements and is refused. We did not check
  the production image ourselves.

**The third program** (222 lines) fixes the three defects noted in section
3.14.

| Defect | Change |
| --- | --- |
| Gave up after one error from the shop | Up to three tries when the shop or the network fails. A payment is sent again unchanged, so it can be settled once at most |
| Its answer filled `paid` even when refused | `settled` is true only with the shop's receipt; `signed` is what the agent authorised |
| Unbounded spending by any caller | A budget of 0.05 USDC for the life of the key. Every signed payment counts, settled or not. A restart clears the count and destroys the key; a new key pays only after the sponsor enrolls it |

It was tested on a local chain against the x402 reference facilitator and a
shop that fails on purpose: seven checks out of seven.

**The run**, on the machine of section 3.14 restarted with the new
compose file.

| Step | Result |
| --- | --- |
| Compose hash computed from the repository before deployment | `494249cb…00a3`; the provider, then the machine, gave the same value |
| Code identity computed from that hash | Found in the machine's quote |
| `DstackConfigIdVerifier.attest` ([tx](https://sepolia.basescan.org/tx/0xb45304401f2764824fffd3af7efccda99c89353e94110ea695926cfebab008b2)) | 3,719,408 gas |
| `enroll`, no attester signature ([tx](https://sepolia.basescan.org/tx/0x4fc2101c5ef4e9d7ab1f1c06b50af27904d95eed6963ef61448b55a25727378e)) | 199,370 gas; the account appears at the address computed beforehand |
| The agent buys while its account is empty | Refused by the facilitator (`invalid_exact_evm_insufficient_balance`); `settled` is false and the budget is charged |
| Four more attempts, then two more | The four are refused the same way and bring the budget to zero; the program then refuses to sign (`budget spent`) |
| Machine stopped, account funded with 20 test USDC, machine restarted | A new key and a fresh count; it buys before being enrolled and is refused (`invalid_exact_evm_signature`) |
| New quote, rotation ([tx](https://sepolia.basescan.org/tx/0x7697a4575335cf7cdd6b5502d1c999fc82bc4403103150c56d3df820efd1fcf7)) | 43,670 gas |
| Four purchases ([first](https://sepolia.basescan.org/tx/0xeb9af69f1d33e8939ae407097ea5c54b93b9d151fbbe0993920faa368c63dbfa), [fourth](https://sepolia.basescan.org/tx/0x2ca56538e4a2332da6737acb1be2e93f8e2bfe3384ff576d800006fd8d1875d8)) | Paid, `settled` true each time; 19.96 USDC left |
| Two more attempts | The program refuses to sign (`budget spent`): four payments settled and one refused had used the budget of that key |

The retry could not be provoked on the public shop and is covered by the local
test only. The budget bounds what a caller can make the agent spend; it does
not say who may ask, and it lives in the machine's memory.

**A limit this run made visible: a new version was a new agent.** The
verifier's list of approved code is fixed at deployment, and so was the
registry's verifier. Fixing the program therefore meant a new verifier, a new
registry and a new account; the 19.96 test USDC of the second agent stay on its
account, which only a machine running the second program can use. Section 3.16
removes this limit.

### 3.16 Upgrading the program without changing the account

Done on 16 November 2026, to remove the limit found in section 3.15.

**The rule.** The registry's attesters can replace its enrollment verifier
(`setEnrollmentVerifier`), with the same signatures, threshold and replay
protection as for venues. Nothing else changes.

- **What stays.** The agent's id, its account, its tokens, and its current
  key until it expires or is replaced.
- **What changes.** The agent's next key must satisfy the new verifier. A
  program the new verifier does not list can no longer obtain a key: it dies
  out within one key lifetime, 30 days in our deployments.
- **Cost.** One more storage read per enrollment, about 2,150 gas (section
  3.9). Transfers do not read the verifier.

**Why this shape.**

| Option considered | Why it was not kept |
| --- | --- |
| The sponsor approves new code for its own agent | The sponsor is a human. It could approve a program that hands it the key, and "no human" would no longer hold |
| A verifier whose list of programs can grow | Every verifier would need its own access rule. An immutable verifier is a fixed, checkable statement of what it accepts |
| A waiting period before a new verifier takes effect | Venue approvals take effect at once and carry the same risk. A delay on one and not the other would protect nothing. A delay on both is a possible hardening (section 8) |

Replacing the verifier is also the way to change the DCAP verifier, the
accepted platform level, or to move to a zk route, without a new registry.

**What it costs in trust.** Before this change, a registry deployed with a
verifier could never enroll a key without the proof. Now two of three attesters
can install a verifier that accepts anything. They could already approve a
venue that hands tokens to humans, so the class of trust is the same; but the
hardware proof no longer binds the attesters themselves. Each replacement emits
an event, and the deployment emits the first one.

**Tested.** Four tests on the real quotes: an upgrade from the first program
to the second keeps the account and its tokens; one attester, another verifier
address, another evidence hash or a replayed decision is refused; removing the
verifier returns enrollments to attester signatures. Removing any of the 8
added checks makes a test fail.

**Run on Base Sepolia**, on the machine of the previous sections.

| Step | Result |
| --- | --- |
| A registry whose verifier approves the second program only | [`0x2D01…06b3`](https://sepolia.basescan.org/address/0x2D01ac2608DD8e898080C6C6c2ae1d7Ff01106b3) |
| The machine runs the second program; quote verified, agent enrolled ([tx](https://sepolia.basescan.org/tx/0xe9ac0662bbc47b366c2d7b05838a3899df0b00b1d0b02f947c0d8a47e1f3a6e1)) | Account [`0xd960…86ED`](https://sepolia.basescan.org/address/0xd960545936a5D167356D8922C6E45198665786ED) |
| The agent mints ([tx](https://sepolia.basescan.org/tx/0xefc45cb0d57022b76c87e430cf8514d7958023a7dc1b87da1c66dbfcc4a03285)) | One token |
| The machine is updated to the third program: a new key, a new quote, verified by the third program's verifier | The registry still asks the first verifier: enrolling that key is refused (`NotVerified`), and so is its order (`NotKey`) |
| Two of the three attesters replace the verifier ([tx](https://sepolia.basescan.org/tx/0x1e8b0e4211dc25b81e61380caa9442f1cc7163b5a8503e89eb68087456d65df1)) | 68,095 gas. The same signatures sent again are refused (`BadAttester`) |
| The new key is enrolled ([tx](https://sepolia.basescan.org/tx/0xd7068b33141d8984cac30c54b0297c71308fcdf19824b69e16c130eebe0d59f1)) | 45,950 gas. Same agent id, same account |
| The agent mints again ([tx](https://sepolia.basescan.org/tx/0x9224ec4f09d2809fc998540294852080b8b8bb9b5ccb4a5b32fceb756b20477d)) | The account holds both tokens |

The two refusals before the decision were simulated on the chain's state one
block earlier; the other steps are transactions.

**Loan repayments, fixed the same day.** A repayment used to be sent straight
to the lender, so a lender that could not receive the currency (blocklist,
receive hook) could make it fail and then claim the collateral. Repayments now
wait in the venue and the lender withdraws them. One test with a blocklisting
currency; 4 more mutation checks.

## 4. Use cases

The standard is content-agnostic: the token can be anything an ERC-721 can be.
The table separates what was tested from what is only supported by design.

| Use case | How it works | Status |
| --- | --- | --- |
| Liquidity positions | An agent wraps a Uniswap V3 position; it can then be sold or pledged between agents only, and managed through the wrapper | Tested against the official Uniswap V3 bytecode |
| Sale between agents | Fixed-price listing; NFT and payment token move in one transaction | Tested |
| Collateralised loans between agents | The borrower pledges a token, the lender funds; on default the lender, also an agent, receives it | Tested |
| Existing NFT collections | Any ERC-721 can be made agent-only through the wrapper | Tested with a generic ERC-721 |
| Art and collectibles made for agents | A collection inherits the standard; unlike existing projects, resale stays between agents | Supported by design; mint and transfer rules tested |
| Documents and credentials | A non-monetary token (certificate, administrative record, licence) that only agents can hold or pass on | Supported by design; no specific test |
| Agent identity and reputation | The registry can require that the sponsor owns the agent's ERC-8004 identity. Reputation badges are soulbound: an issuer offers one for a piece of work, the agent claims it, and it never moves | Tested |
| Staking | The agent deposits its NFT in a staking venue and earns an ERC-20 reward stream shared equally per staked NFT; only the staker gets the NFT back | Tested, including in the invariant test |
| Lending positions (Aave, Morpho, Compound) | These are not NFTs, so the wrapper does not apply. A token-bound account (ERC-6551) per token is the candidate route | Not covered, not tested |
| Payments for services around the token (x402) | The agent's session key signs an EIP-3009 USDC authorisation as a message of its account; USDC confirms it through ERC-1271 and a facilitator submits it. The agent needs no ETH (section 3.10) | A paid API bought through the x402 reference facilitator on a local chain; a public demonstration page bought on Base Sepolia by an agent in a confidential VM, through a hosted facilitator (section 3.14). No payment on a main network |

**Open question.** What does holding the token give an agent? Without a clear
answer, no autonomous agent has a reason to buy, borrow against, or lend on it.
Each collection has to answer this for itself.

## 5. Security

**One rule governs everything: a prompt is not a control.** Every limit must be
enforced by deterministic code or by the contract, never by an instruction
given to the model.

| Threat | What the contracts do | What an agent runtime must do |
| --- | --- | --- |
| Unsolicited token used to escalate permissions | Rule 3: an agent only receives what it pulls | Never derive a permission from holding a token |
| Injection through metadata, name or `tokenURI` | Nothing: the token cannot inspect content | Treat all token content as untrusted data; keep free text out of decisions |
| Approval or `permit` drainer | Approvals only go to agents and approved venues. The account's key only signs EIP-712 typed data bound to that account | Sign typed data only; no generic `sign(bytes)` |
| EIP-7702 delegation trap | Eligibility never depends on the presence of code | Refuse that message type |
| Replay of a relayed call | Per-account nonce and deadline, in typed data bound to the chain and the account | |
| Replay of an attester decision | Counter per agent for enrollments, per venue for approvals and removals | |
| Off-chain message reused as an order | Orders and messages are distinct EIP-712 types | |
| Seller or borrower changing terms at the last moment | The buyer or lender states the terms it agreed to | Never rely on a listing read in an earlier block |
| Stolen or leaked session key | Keys expire and are replaced at the next enrollment; the sponsor can freeze, and a frozen holder's tokens do not move, even through a listing left behind | Keep the key inside the attested runtime |
| False proof of agent | Attesters can revoke; the bond is forfeited | |
| Compromised attester | A threshold of signatures is required | |
| Dishonest approved venue | Nothing once approved | Attesters must review venue code before approving |
| Sybil and spam | Refundable bond per agent | |
| Operator with physical access to the TEE | Outside the reference registry | Enroll only hardware hosted where the operator has no physical access; see next section |

Before any deployment holding value: invariant fuzzing, an injection corpus
replayed at each version, an external audit of contracts and runtime, then a
bug bounty.

## 6. A stronger proof of agent, for later

The reference registry trusts attesters. The target is a registry that verifies
the proof on-chain. The standard does not depend on it: only the registry
changes.

| Decision | Choice | Why |
| --- | --- | --- |
| First-level proof | Intel TDX attestation, verified on-chain at each enrollment. First building block written: section 3.11 | Verifiable by a contract, [about 4 to 5M gas directly or about 500k with a zk proof](https://github.com/automata-network/automata-dcap-attestation). A dstack VM needs one more step: [its last register differs for each instance](https://github.com/Dstack-TEE/dstack/blob/master/docs/attestation-tdx.md), so its event log must be replayed |
| Where the hardware runs | Only machines listed in the [Proof of Cloud](https://proofofcloud.org/) registry | Closes the attack by an operator with physical access |
| Key custody | Ephemeral enclave key, recreated at each start | Nothing durable to steal. A persistent key derived by a KMS is discarded: [the application owner can authorise new code](https://docs.phala.com/phala-cloud/key-management/understanding-onchain-kms) |
| Model | Open model served by confidential inference on attested GPU, with signed responses | A capable model without a GPU in the agent |
| Role of the model | It fills a typed decision inside a control flow written in code | The [CaMeL](https://arxiv.org/abs/2503.18813) principle: security comes from architecture |
| Second-level proof | Above a value cap, a second approval from an instance on another vendor or cloud | Two systems must be broken, as in Taiko's multi-proof design |

What this still requires trusting: Intel and Nvidia for attestations; the Proof
of Cloud alliance, which states that it does not guarantee against all physical
attacks; the confidential inference provider; and whoever sets the list of
accepted agent code, which must be immutable or changeable only after a long
public delay.

Options studied and set aside:

- **NEAR Shade Agents.** The [NEAR documentation](https://docs.near.org/ai/shade-agents/concepts/terminology)
  states that the framework has not been maintained since 19 April 2026.
- **zk proof of inference as the main lock.** Too heavy today and not
  verifiable in a contract.
- **Key held by an MPC network.** It protects the key, not the enrollment.
- **Fully on-chain agent driven by an inference oracle**, such as
  [ORA's OAO](https://ethresear.ch/t/oao-onchain-ai-oracle/18675). No operator
  machine and no key, so no physical attack by the holder. Set aside for now:
  restricted model choice and delayed finality.

## 7. Limits and what was not done

- **Trust in attesters**, for agents and venues. Attesters are fixed at
  deployment.
- **Hardware attestation.** Three agents were enrolled by attestation, on Base
  Sepolia, from two machines of one provider (sections 3.13 to 3.15). The
  base image was not rebuilt from source. The provider's pre-launch script,
  part of the measured manifest, installs SSH keys from a file dstack does not
  measure: an agent's key is only as private as the approved base image is
  closed to SSH, which was not checked (section 3.15).
- **The attesters can replace the enrollment verifier.** A program can be
  upgraded without changing the account, but the hardware proof binds a
  registry only as long as its attesters keep a verifier that demands it.
  Nothing delays a replacement (section 3.16).
- **dstack key provider.** The dstack verifier checks the code, not the
  `key-provider` event nor the application's environment variables. Approved
  code must keep its session key in memory only (section 3.11).
- **Loan currencies that take a fee on transfers** are not supported: the
  venue would owe lenders more than it holds.
- **The standard protects the NFT, not what it yields.** Tokens withdrawn from
  a position are ordinary ERC-20s.
- **Selling a position.** The buyer must check its liquidity in the same batch
  as the purchase, otherwise the seller can empty it right before. Fees already
  earned can always be collected by the seller before selling.
- **Removed venues.** If attesters remove a venue while it holds tokens, those
  tokens are stuck until the venue is approved again.
- **Human lenders.** A human can lend through the loan venue but can never
  receive the token: on default it stays in the venue until the borrower repays.
- **Stranded NFTs.** A classic NFT sent to a wrapper with a plain
  `transferFrom`, instead of `depositFor`, is stuck there.
- **Emptied positions** stay in a non-unwrappable wrapper; burning is not
  provided.
- **Retired or revoked agents.** Their tokens stay where they are.
- **x402.** Payments were made on a local chain and on Base Sepolia, through
  the reference code and the hosted x402.org test facilitator. A production
  facilitator may run other code, and USDC is upgradeable (sections 3.10 and
  3.14).
- **Not tested.** Uniswap V4, any other protocol, ERC-20 and ERC-1155 profiles.
- **Measured on a test network only.** Real fees, L1 data fee included, come
  from Base Sepolia (section 3.12).
- **Noted by the independent review, not fixed.** Anyone can take a free agent
  id first when no identity registry is set. After an ERC-8004 identity changes
  hands, the old sponsor keeps its rights. An approved dstack application that
  quotes any data a caller chooses would let that caller enroll a key: approved
  code must only quote enrollment digests of keys it created. The dstack
  verifier trusts that no application code runs before `boot-mr-done`. An
  application that logs more than 64 events cannot enroll.
- **Not done.** Deployment on a main network, professional audit. The third review
  (section 2.5) uses an independent agent, symbolic proofs and fuzzing; it does
  not replace a human audit before real value is at stake.

## 8. Proposed next steps

1. Done on 16 November 2026 (sections 3.13 and 3.14): quotes produced by two
   real dstack machines for our keys, two agents enrolled by attestation, and
   a verifier reading the compose hash from `MRCONFIGID`. The manifest was
   then rebuilt and the pre-launch script read (section 3.15). Next on that
   path: a base image rebuilt from dstack's sources and checked for SSH, a
   pre-launch script of our own, and the same build on two machines at once.
2. Done on 16 November 2026 (section 3.14): x402 payments from an agent
   account on Base Sepolia, through a hosted facilitator, then a budget per
   key (section 3.15). Next: a purchase whose result the agent uses.
3. Done on 16 November 2026 (section 3.16): the attesters can replace the
   enrollment verifier, so a program is upgraded without changing the account.
   Next: a waiting period on every decision that widens who can hold tokens
   (venue approval and verifier replacement), so holders can see it coming.
4. Enrollment through a zk proof of the quote verification, about 500,000 gas
   instead of 4.3 million. Checked on chain on 15 November 2026: RISC Zero's
   verifier router is deployed on Base Sepolia, but Automata's entrypoint
   there has no zk program configured, so its `verifyAndAttestWithZKProof`
   cannot be used as it is.
5. Publication of the idea on [Ethereum Magicians](https://ethereum-magicians.org/),
   then a pull request to [ethereum/ERCs](https://github.com/ethereum/ERCs)
   once a second implementation passes the same tests.

## 9. Verification log

Only what was re-read at the source is listed. A statement in this document
that does not appear here was not re-checked. Checked on 11 November 2026
unless stated otherwise.

| Claim | Result | Source |
| --- | --- | --- |
| ERC-8273 exists, in Draft, and binds an attestation to a specific action | Confirmed, page read in full | [ERC-8273](https://eips.ethereum.org/EIPS/eip-8273) |
| ERC-8196 is Final | Confirmed | [ERC-8196](https://eips.ethereum.org/EIPS/eip-8196) |
| ERC-7992, 8004, 8354, 8217 and 7857 exist and cover what is said of them | Confirmed on excerpts | EIP pages listed in sources |
| ERC-7066 is Final and locks an NFT in the wallet for loans, rentals and staking | Confirmed | [ERC-7066](https://eips.ethereum.org/EIPS/eip-7066) |
| ERC-6551 is in Review | Confirmed on 12 November 2026 | [ERC-6551](https://eips.ethereum.org/EIPS/eip-6551) |
| ERC-3643 is Final | Confirmed on 12 November 2026 | [ERC-3643](https://eips.ethereum.org/EIPS/eip-3643) |
| Lobros filters the mint with a maths challenge then a backend co-signature | Confirmed | [lobros.fun](https://www.lobros.fun/) |
| Agentic Proof of Work imposes a timed challenge | Confirmed: 20 seconds | [apow-core](https://github.com/Agentoshi/apow-core) |
| Machine Readable Only lets humans own and trade its tokens | Confirmed, stated by the project | [llms.txt](https://machinereadableonly.com/llms.txt) |
| No "agent-only" project restricts resale | Confirmed for three: Lobros, Agentic Proof of Work, Machine Readable Only. Not checked for the others | Project pages |
| A Seaport sale requires an approval from the seller | Confirmed: to Seaport, or to a conduit if one is named | [Seaport](https://docs.opensea.io/docs/seaport-models) |
| A Rarible sale requires an approval from the seller | Confirmed: approval of its exchange contracts | [rarible/protocol-contracts](https://github.com/rarible/protocol-contracts) |
| Whoever controls a dstack application can authorise new code | Confirmed: the application owner calls `addComposeHash`. That role can be given to a multisig or a timelock | [Phala on-chain KMS](https://docs.phala.com/phala-cloud/key-management/understanding-onchain-kms) |
| That new code obtains the same key | Confirmed: the key depends on the application and the instance, not on the code version | [dstack issue 1297](https://github.com/Dstack-TEE/dstack/issues/1297) |
| TEE.fail allows forging attestations | Confirmed, including against dstack and Nvidia GPU attestation | [IEEE S&P 2026 poster](https://www.ieee-security.org/TC/SP2026/downloads/posters/sp2026posters-final75.pdf) |
| Proof of Cloud binds a hardware id to a verified data centre | Confirmed. The alliance states it does not guarantee against all physical attacks | [proofofcloud.org](https://proofofcloud.org/) |
| A contract can read the Proof of Cloud registry | **Open**: the site only describes a verification form | Same |
| An attestation does not say where the machine is | Confirmed by the founding paper | [Proof of Cloud, arXiv](https://arxiv.org/abs/2510.12469) |
| NEAR Shade Agents has not been maintained since 19 April 2026 | Confirmed | [NEAR documentation](https://docs.near.org/ai/shade-agents/concepts/terminology) |
| FlashProve was tested on Llama 4 Maverick with a 1,024-token window | Confirmed on press reports only | [Crypto Briefing](https://cryptobriefing.com/anthropic-flashprove-zksnark-ai-inference/) |
| The x402 `exact` EVM specification describes a 65-byte signature that recovers to the payer | Confirmed again on 13 November 2026 | [x402 exact scheme](https://github.com/x402-foundation/x402/blob/main/specs/schemes/exact/scheme_exact_evm.md) |
| The x402 reference facilitator nevertheless verifies a payer that has code through ERC-1271, and settles a 65-byte signature with the (v, r, s) form | Read in the code at commit `1a08434` (13 November 2026), then executed on 14 November 2026: packages `@x402/core` and `@x402/evm` 2.31.0, local chain, agent payer accepted and settled (`examples/x402`) | [eip3009.ts](https://github.com/x402-foundation/x402/blob/1a084343e165d6f61b60b34f6146d6e4a4a7f3ca/typescript/packages/mechanisms/evm/src/exact/facilitator/eip3009.ts) |
| USDC `FiatTokenV2_2` checks contract payers through ERC-1271, in both forms of `transferWithAuthorization` | Confirmed by test against the compiled source, commit `fc85788` | [circlefin/stablecoin-evm](https://github.com/circlefin/stablecoin-evm) |
| Automata DCAP Attestation returns, for a verified quote, its version, body type, security level, platform family and report body, in that order | Read in the source at tag `v1.2.0` (`serializeOutput`), 14 November 2026, then confirmed by execution on Base Sepolia on 15 November 2026 (section 3.12) | [automata-dcap-attestation](https://github.com/automata-network/automata-dcap-attestation/tree/v1.2.0) |
| Automata's verifier does not check the debug flag of a TDX machine | Read in the same source: no test of the machine's attributes in the V4 and V5 verifiers. Not executed | Same |
| Automata DCAP Attestation is deployed on Base | Stated by its repository (`deployment/current/8453`). **Not checked on-chain** | Same |
| Automata DCAP Attestation is deployed on Base Sepolia and verifies a real TDX quote | Confirmed on 15 November 2026 by a transaction through our verifier (section 3.12) | [BaseScan](https://sepolia.basescan.org/tx/0x713be5c31abcd1fed0ce5923725520330b3ea0d0d99bcc3241cc55a14241110c) |
| dstack logs the key provider in RTMR3 and tells verifiers to check it against what they expect | Read in its attestation guide on 16 November 2026 (section 2.1 and conclusion). Our verifier does not check it (section 3.11) | [dstack attestation](https://github.com/Dstack-TEE/dstack/blob/master/docs/attestation-tdx.md) |
| A Phala Cloud machine's quote is accepted by Automata's verifier on Base Sepolia, and dstack writes `compose-hash` before `boot-mr-done` | Confirmed on 16 November 2026 by transaction (section 3.13) | [BaseScan](https://sepolia.basescan.org/tx/0x3bde5e7d3ccf206d60290a8b9de98ae72ea5d79f2fc6368141c3e652613b9fcf) |
| dstack writes the compose hash into `MRCONFIGID` (format `01`) and its OS refuses to boot when the field does not match the manifest; an all-zero field is tolerated | Read in the source at commit `350a0a7` on 16 November 2026. The field's content was confirmed on the quotes of two production machines; the refusal to boot was not provoked | [config_id_verifier.rs](https://github.com/Dstack-TEE/dstack/blob/350a0a73ffdb6041bda69118f13d81591870b565/dstack/dstack-util/src/system_setup/config_id_verifier.rs) |
| The pre-launch script our machines ran is the public one, version 0.0.21 | Confirmed on 16 November 2026: same SHA-256 (`c452d712…0765`) as the file at commit `3811c90`, and the manifest rebuilt with it gives the four compose hashes measured | [prelaunch.sh](https://github.com/Dstack-TEE/dstack-examples/blob/3811c903df9643b68d5510b0a63828384ab2c1c3/phala-cloud-prelaunch-script/prelaunch.sh) |
| dstack does not measure `user_config` | Read in its documentation at commit `350a0a7` (`docs/security/cvm-boundaries.md`), 16 November 2026. Not tested | [dstack](https://github.com/Dstack-TEE/dstack/blob/350a0a73ffdb6041bda69118f13d81591870b565/docs/security/cvm-boundaries.md) |
| The hosted x402.org facilitator accepts a payer that is a contract and settles its payment | Confirmed on 16 November 2026 by four payments on Base Sepolia from an agent account (section 3.14) | [BaseScan](https://sepolia.basescan.org/tx/0x89e0a73920d855494cbad29a8ec0035a4e07c84da12e409b6c1e2f74aade5ea0) |
| The test USDC on Base Sepolia is `FiatTokenV2_2` | Confirmed on 16 November 2026 at block 59,533,350: the implementation `0xd74cc5d436923b8ba2c179b4bca2841d8a52c5b5` and its signature library are byte-identical to the code these tests use, apart from the metadata hash and the library address | `examples/x402/check-usdc.mjs` |
| Two machines of the same provider running the same dstack image give the same attributes, MRTD and RTMR0 to RTMR2 | Confirmed on 16 November 2026 by comparing the quotes of the two runs, byte for byte | `test/experimental/phala` |
| In dstack, the last runtime register contains the instance id and differs for each instance | Confirmed in its documentation, commit `b936f86` (13 November 2026) | [dstack attestation](https://github.com/Dstack-TEE/dstack/blob/master/docs/attestation-tdx.md) |
| dstack extends RTMR3 as SHA-384(RTMR3 \|\| event digest) from zero; V1 digest = SHA-384(type LE \|\| ":" \|\| name \|\| ":" \|\| payload) | Read in `cc-eventlog/src/runtime_events.rs` (commit `b936f86`), then confirmed on 15 November 2026 by replaying the real event log of `verifier/fixtures/quote-report.json`, offline and in the tests | [dstack](https://github.com/Dstack-TEE/dstack) |
| The USDC deployed on Base is `FiatTokenV2_2` | Confirmed on 14 November 2026 at block 57,208,253: the implementation `0x2Ce6311ddAE708829bc0784C967b7d77D19FD779` and its signature library are byte-identical to the code compiled from commit `fc85788`, apart from the metadata hash and the library address. Read through the public RPC `https://mainnet.base.org` | `examples/x402/check-usdc.mjs` |
| The standard x402 client pays from an agent account once given the 28-line signer adapter | Confirmed by execution on 14 November 2026: packages `@x402/fetch` and `@x402/express` 2.31.0, local chain | `examples/x402/demo.mjs` |

## 10. Sources

**Standards**

- [ERC-721](https://eips.ethereum.org/EIPS/eip-721), [ERC-3643](https://eips.ethereum.org/EIPS/eip-3643), [ERC-6551](https://eips.ethereum.org/EIPS/eip-6551)
- [ERC-8273: Attestation-Gated Agentic Actions](https://eips.ethereum.org/EIPS/eip-8273)
- [ERC-8274: AI Inference Proof Verification (discussion)](https://ethereum-magicians.org/t/erc-8274-ai-inference-proof-verification/28083)
- [ERC-7992: Verifiable ML Model Inference](https://eips.ethereum.org/EIPS/eip-7992)
- [ERC-8004: Trustless Agents](https://eips.ethereum.org/EIPS/eip-8004) and [deployment status (Taiko)](https://taiko.xyz/guides/erc-8004-trustless-agent-standard)
- [ERC-8126](https://eips.ethereum.org/EIPS/eip-8126), [ERC-8196](https://eips.ethereum.org/EIPS/eip-8196), [ERC-8217](https://eips.ethereum.org/EIPS/eip-8217), [ERC-8354](https://eips.ethereum.org/EIPS/eip-8354), [ERC-7857](https://ercs.ethereum.org/ERCS/erc-7857)
- [ERC-7066: Lockable Extension](https://eips.ethereum.org/EIPS/eip-7066), [ERC-4907: Rental NFT](https://eips.ethereum.org/EIPS/eip-4907)
- [Creator Token Standards / ERC-721C (Limit Break)](https://medium.com/limit-break/creator-token-standards-building-guardrails-for-your-tokens-3b261cdd3027) and [enforcement by OpenSea](https://docs.opensea.io/docs/creator-fee-enforcement)
- [x402 v2](https://www.x402.org/writing/x402-v2-launch) and [`exact` EVM scheme](https://github.com/x402-foundation/x402/blob/main/specs/schemes/exact/scheme_exact_evm.md)
- [A map of the agent mandate ERCs (Ethereum Magicians)](https://ethereum-magicians.org/t/a-map-of-the-agent-mandate-ercs-what-each-one-actually-does/29421)

**Execution and proof**

- [dstack](https://github.com/dstack-TEE/dstack), [ERC-8004 agent in a TEE (Phala)](https://docs.phala.com/phala-cloud/getting-started/explore-templates/deploy-erc-8004-agent), [Phala on-chain KMS](https://docs.phala.com/phala-cloud/key-management/understanding-onchain-kms), [dstack issue 1297](https://github.com/Dstack-TEE/dstack/issues/1297)
- [Oasis ROFL](https://oasis.net/blog/multichain-wallet-agents)
- [Automata DCAP](https://docs.ata.network/tee-overview/tee-verifiers/intel-sgx-tdx-dcap)
- [Proof of Cloud](https://proofofcloud.org/), [founding paper](https://arxiv.org/abs/2510.12469), [Phala statement](https://phala.com/posts/phala-ddr5), [Secret Network response](https://scrt.network/blog/secret-labs-response-to-tee-fail-ddr5-vulnerability)
- [Physical integrity, attestation, and the state of permissionless TEEs (ethresear.ch)](https://ethresear.ch/t/physical-integrity-attestation-and-the-state-of-permissionless-tees/24964)
- [EigenAI](https://blog.eigencloud.xyz/deterministic-ai-inference-eigenai/)
- [FlashProve (Anthropic)](https://www.anthropic.com/research/provable-inference) and [reported figures](https://cryptobriefing.com/anthropic-flashprove-zksnark-ai-inference/)
- [zkTLS for agents (Wavect)](https://wavect.io/blog/zktls-ai-agents/), [Reclaim llm-x402](https://github.com/reclaimprotocol/llm-x402)
- [OAO, on-chain AI oracle (ORA)](https://ethresear.ch/t/oao-onchain-ai-oracle/18675)
- [Shade Agents deprecation notice (NEAR)](https://docs.near.org/ai/shade-agents/concepts/terminology)

**Security**

- [TEE.fail (The Hacker News)](https://thehackernews.com/2025/10/new-teefail-side-channel-attack.html), [BleepingComputer](https://www.bleepingcomputer.com/news/security/teefail-attack-breaks-confidential-computing-on-intel-amd-nvidia-cpus/amp/), [IEEE S&P 2026 poster](https://www.ieee-security.org/TC/SP2026/downloads/posters/sp2026posters-final75.pdf)
- [Indirect prompt injection and the Bankrbot incident (Zealynx)](https://www.zealynx.io/research/adversarial-security/indirect-prompt-injection)
- [AI Agents in Cryptoland (Princeton)](https://arxiv.org/abs/2503.16248)
- [EIP-7702 and account assumptions (CertiK)](https://www.certik.com/blog/pectras-eip-7702-redefining-trust-assumptions-of-externally-owned-accounts)
- [CaMeL (Google DeepMind)](https://arxiv.org/abs/2503.18813)

**Marketplaces and "agent-only" projects**

- [Seaport](https://docs.opensea.io/docs/seaport-models), [rarible/protocol-contracts](https://github.com/rarible/protocol-contracts)
- [Lobros](https://www.lobros.fun/), [Agentic Proof of Work](https://github.com/Agentoshi/apow-core), [Machine Readable Only](https://machinereadableonly.com/llms.txt), [Shellborn](https://www.shellborn.io/), [No Human Allowed](https://www.nohumanallowed.com/), [AgenticNFT](https://github.com/wizard0x0/agentic_only_nft), [Printer AI](https://agentprinter.netlify.app/), [PairMine](https://github.com/pairmineai/pairmine-skill), [ClawMint](https://clawmint.io/)
