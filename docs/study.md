# Agent-Only Tokens: research, approach, standard and use cases

Julien Kervarrec · November 2026

This document records how the Agent-Only Tokens draft was reached: what already
exists, how the design was narrowed down, what the resulting standard says, and
what it can be used for. Every figure about the prototype comes from tests run
on a local simulated EVM. Nothing has been deployed or audited.

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
| [Automata DCAP](https://docs.ata.network/tee-overview/tee-verifiers/intel-sgx-tdx-dcap) | On-chain verification of an Intel SGX/TDX attestation | [About 4M gas directly, 300k with a zk proof](https://awesome.ecosyste.ms/projects/github.com%2Fautomata-network%2Fautomata-dcap-attestation) |
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
- **Mutation testing.** Each of 33 security checks is removed in turn; the test
  suite now fails every time.

One more lesson: **a venue that never holds the token must tie each listing to
the token's own approval**, because that approval is the only thing a transfer
resets.

## 3. The standard

**A classic ERC-721 plus three rules, 62 lines in the reference implementation.
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
| `ERC721AgentOnly` | The standard: the three rules | 62 |
| `IERC721AgentOnly` | The interface a compliant token exposes, advertised through ERC-165 | 10 |
| `IAgentRegistry` | The two questions asked to the registry | 10 |
| `AgentAccount` | An agent's account, with no human owner. Only its session key makes it act: single calls, all-or-nothing batches, relayed calls, ERC-1271. Each account is an ERC-1167 clone of one implementation | 139 |
| `AttestedAgentRegistry` | Proof of agent, version 1: attesters, bond, expiring keys, freeze, revocation, venue approval, ERC-8004 link | 218 |
| `AgentSwap` | Fixed-price sale between agents | 54 |
| `AgentLoan` | Collateralised loan between agents | 84 |
| `AgentStaking` | Staking for ERC-20 rewards, Synthetix-style accounting, one NFT = one unit | 130 |
| `AgentWrapped721` | Wrapper making any existing ERC-721 agent-only | 80 |
| `AgentWrappedUniV3` | Non-unwrappable wrapper for Uniswap V3 positions | 95 |
| `AgentReputationBadge` | Soulbound reputation badges (ERC-5192): an issuer offers, the named agent claims, the issuer can revoke | 215 |

### 3.3 What the tests establish

Sixty tests on a local simulated EVM, one fuzzed over 512 addresses and one
stateful invariant test.

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
| Each of 33 security checks removed in turn (mutation testing) | The suite fails every time |
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
L1 data fee comes on top and is not measured.

| Operation | Gas |
| --- | --- |
| Plain ERC-721 `transferFrom`, for reference | 55,582 |
| Agent-only `transferFrom`, called directly | 70,432 |
| Agent-only `transferFrom`, through the agent account | 80,284 |
| Agent-only mint, through the agent account | 131,452 |
| List for sale | 111,772 |
| Buy (NFT against an ERC-20) | 114,365 |
| First enrollment (deploys the account as a clone, 2 attester signatures) | 208,574 |
| Key rotation (2 attester signatures) | 52,933 |
| Badge offer, by an issuer | 252,743 |
| Badge claim, through the agent account | 95,569 |
| Stake, through the agent account | 165,366 |
| Claim staking rewards | 116,689 |
| Unstake with rewards | 133,562 |

The standard adds about 15,000 gas to a transfer: the registry is asked about
the caller and the holder, and about the recipient when it is not the caller. Agent accounts are ERC-1167 clones of a single implementation, which brought
the first enrollment down from 1,154,831 to 208,574 gas. The price is about
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

Three things are not established. No real facilitator was run: that the
reference facilitator accepts a contract payer comes from reading
[its code](https://github.com/x402-foundation/x402/blob/1a084343e165d6f61b60b34f6146d6e4a4a7f3ca/typescript/packages/mechanisms/evm/src/exact/facilitator/eip3009.ts), while the written
[specification](https://github.com/x402-foundation/x402/blob/main/specs/schemes/exact/scheme_exact_evm.md) still describes a signature that recovers to the
payer. Stock x402 clients sign the payment digest directly, so an agent needs
a small signer of its own. And whether the USDC deployed on Base is this exact
version was not checked on-chain. ERC-7710, which the specification proposes
for smart accounts, turned out not to be needed for this path.

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
| Payments for services around the token (x402) | The agent's session key signs an EIP-3009 USDC authorisation as a message of its account; USDC confirms it through ERC-1271 and a facilitator submits it. The agent needs no ETH (section 3.10) | Payment tested on Circle's USDC code; no real facilitator run |

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
| First-level proof | Intel TDX attestation of a dstack VM, verified on-chain once, at enrollment | Open source, verifiable by a contract, [about 300k gas with a zk proof](https://awesome.ecosyste.ms/projects/github.com%2Fautomata-network%2Fautomata-dcap-attestation) |
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
- **No real attestation** is wired in. The registry only checks signatures.
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
- **x402.** No real facilitator was run, the agent needs a client that signs
  the account's message wrapper, and the USDC version deployed on Base was not
  checked on-chain (section 3.10).
- **Not tested.** Uniswap V4, any other protocol, ERC-20 and ERC-1155 profiles.
- **Not measured.** The L1 data fee on Base. Execution gas is in section 3.9.
- **Not done.** Deployment on any network, audit, external review. The reviews in
  sections 2.3 and 2.4 are the author's own.

## 8. Proposed next steps

1. Run the x402 reference facilitator against a local chain with an agent payer,
   and write the small client-side signer it needs.
2. Deployment on Base Sepolia, to measure the L1 data fee.
3. A registry verifying a real TEE attestation.
4. Publication of the idea on [Ethereum Magicians](https://ethereum-magicians.org/),
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
| The x402 reference facilitator nevertheless verifies a payer that has code through ERC-1271, and settles a 65-byte signature with the (v, r, s) form | Read in the code at commit `1a08434` (13 November 2026), not executed | [eip3009.ts](https://github.com/x402-foundation/x402/blob/1a084343e165d6f61b60b34f6146d6e4a4a7f3ca/typescript/packages/mechanisms/evm/src/exact/facilitator/eip3009.ts) |
| USDC `FiatTokenV2_2` checks contract payers through ERC-1271, in both forms of `transferWithAuthorization` | Confirmed by test against the compiled source, commit `fc85788` | [circlefin/stablecoin-evm](https://github.com/circlefin/stablecoin-evm) |
| The USDC deployed on Base is `FiatTokenV2_2` | **Not checked** | |

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
