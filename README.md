# Agent-Only Tokens

A research prototype for an ERC-721 extension whose tokens can only be held and
moved by AI agent accounts. No human-held wallet can mint, receive, transfer,
list, pledge or burn them, including on secondary markets.

**Status: unaudited draft. Deployed on the Base Sepolia test network only, never
on a main network.** Do not use with real assets.

The full study is in [`docs/study.md`](docs/study.md): research and state of
the art, the approach and the designs that were set aside, the standard and
its draft EIP text, use cases, security, a verification log and sources.

## What it can and cannot guarantee

A smart contract cannot prove "this caller is an LLM". What it can enforce is
narrower: every address that holds or moves a token is an account with no human
owner, driven by a session key that a set of attesters vouched for. How strong
"agent" is depends entirely on what those attesters check (for example a TEE
attestation). The standard itself is independent of that proof.

## The standard: three rules on top of ERC-721

`src/ERC721AgentOnly.sol` (70 lines) overrides three OpenZeppelin hooks:

1. Only an agent or an approved venue can hold a token or be approved for it.
2. Only an agent or an approved venue can trigger a mint, transfer or burn.
3. An agent only receives a token if it pulls it itself. Nobody can push an
   unsolicited token to an agent.

A token whose holder is no longer recognised (frozen, expired or revoked) does
not move until the holder is recognised again.

Everything else is plain ERC-721 (`ownerOf`, `approve`, `transferFrom`,
`safeTransferFrom`, `tokenURI`). A collection adopts it with one line of
inheritance and a registry address:

```solidity
interface IAgentRegistry {
    function isAgent(address account) external view returns (bool);
    function isVenue(address account) external view returns (bool);
}
```

## What is in this repository

| File | Role | Lines |
| --- | --- | --- |
| `src/IAgentRegistry.sol` | The two questions asked to a registry | 10 |
| `src/IERC721AgentOnly.sol` | The interface a compliant token exposes, advertised through ERC-165 | 10 |
| `src/ERC721AgentOnly.sol` | The standard: the three rules | 70 |
| `src/AgentAccount.sol` | An agent's account, with no human owner, driven by a rotating session key. Single calls, batches, relayed calls, ERC-1271. Each account is an ERC-1167 clone of one implementation | 139 |
| `src/AttestedAgentRegistry.sol` | Reference registry: k-of-n attesters, refundable bond, expiring keys, optional ERC-8004 identity link, optional enrollment verifier, bond returned after an exit delay | 251 |
| `src/experimental/TdxQuoteVerifier.sol` | Checks shared by the hardware verifiers: the quote is checked by an on-chain DCAP verifier (Automata's interface), accepted platform level, no debug mode, report data holding the digest only | 116 |
| `src/experimental/TdxEnrollmentVerifier.sol` | Enrollment verifier for TDX images whose measurements are the same for every instance | 41 |
| `src/experimental/DstackEnrollmentVerifier.sol` | Enrollment verifier for agents on dstack: replays the RTMR3 event log and identifies the code by its base image and compose hash | 138 |
| `src/experimental/Sha384.sol` | SHA-384, needed to replay TDX registers; the EVM has no precompile for it | 92 |
| `src/AgentSwap.sol` | Fixed-price sale between agents; events announce each listing and sale | 64 |
| `src/AgentLoan.sol` | Collateralised loan between agents; events announce each offer and each step | 104 |
| `src/AgentStaking.sol` | Staking of agent-only NFTs for ERC-20 rewards (Synthetix-style accounting, one NFT = one unit) | 130 |
| `src/AgentWrapped721.sol` | Wrapper that makes any existing ERC-721 agent-only | 80 |
| `src/AgentWrappedUniV3.sol` | Non-unwrappable wrapper for Uniswap V3 liquidity positions | 98 |
| `src/AgentReputationBadge.sol` | Reputation badges: agent-only and soulbound (ERC-5192). An issuer offers, the agent claims; issuers post a refundable deposit and have a daily quota | 218 |
| `examples/x402/` | x402 demo: an agent account buys from a paid API through the x402 reference facilitator, on a local chain. Includes the 28-line signer adapter and a script comparing this repository's USDC code with the one deployed on a chain | |
| `archive/` | Two earlier tracks that were set aside (signed-intent core in Solidity, Rust model) | |

## Running the tests

Requires [Foundry](https://book.getfoundry.sh/) and Node.js.

    npm install
    git clone --depth 1 --branch v1.9.7 https://github.com/foundry-rs/forge-std lib/forge-std
    forge test

The symbolic proofs (`test/halmos`) need [Halmos](https://github.com/a16z/halmos)
(`pip install halmos`):

    halmos --match-contract "AgentOnlyProps|RegistryProps"

The hardware verifiers and SHA-384 are newer and less reviewed than the
standard; they live in `src/experimental`, with their tests and fixtures in
`test/experimental`. Nothing in the standard depends on them.

One hundred and two tests run locally; two more run only against Base
Sepolia and are reported as skipped without an RPC address. They cover: classic ERC-721 behaviour between agents,
refusal of humans as holder, recipient, minter or approved operator, refusal
of unsolicited tokens and of unapproved wrapper contracts, sale, loan (repaid
and defaulted), staking with rewards, session-key rotation, single, batched and relayed calls,
ERC-1271 signatures, attester threshold, freeze and revocation, and the
ERC-8004 identity check, and reputation badges (claim by the named agent only,
no transfer or approval, revocation, issuer deposit, quota and exit).

Four tests pay x402-style invoices on Circle's own USDC code (`FiatTokenV2_2`,
compiled unchanged, see `test/usdc`): an agent account pays a merchant and
another agent, is paid by an ordinary wallet, and cannot pay with a wrong key,
a raw signature, changed terms, or while frozen.

`examples/x402` runs the same payment outside Foundry, through the x402
reference facilitator and the standard x402 client (see "x402 payments" below).

Thirty-four tests cover enrollment by hardware attestation and SHA-384 (see
"Enrollment by hardware attestation" below). They use a real Intel TDX quote
(`test/experimental/tdx`) and a real dstack quote with its event log (`test/experimental/dstack`). In
these local tests a stand-in replaces the DCAP verifier. The real one is
exercised by the two fork tests in `test/fork` and was run on Base Sepolia
(see "Test on Base Sepolia" below).

One test is fuzzed over 512 random addresses. One is a stateful invariant
test: two agents, a human and an unapproved contract perform 128 runs of 100
random actions (mint, approve, transfer, list, buy, lend, repay, claim,
stake, unstake, freeze), and after every action no token may be held by, or approved for,
anything but an agent account or an approved venue. Removing the recipient
check from the standard makes that test fail, as it should.

`test_RealUniswapV3Position` runs against the official Uniswap V3 bytecode
(npm packages `@uniswap/v3-core` 1.0.1 and `@uniswap/v3-periphery` 1.4.4)
deployed in the simulated chain: pool creation, position, wrapping, a
third-party swap, sale to another agent, fee collection by the buyer and
liquidity withdrawal. Further tests on the same bytecode show that a buyer can
check a position's liquidity and buy in one batch, that the holder can add
liquidity directly on Uniswap, and that Uniswap's `permit` cannot move a
wrapped position.

## Adversarial review of 13 November 2026

The first published version was re-read line by line, looking for attacks.
Each flaw below was first reproduced by a test against that version, then
fixed, and the attack is now a regression test.

| Flaw found | Consequence | Fix |
| --- | --- | --- |
| A venue approval carried no counter | After attesters removed a venue, anyone could replay the old signatures and approve it again | One counter per venue, included in what attesters sign |
| The token did not check the current holder | A listing left by a frozen or revoked agent could still be bought, so the emergency stop did not stop everything | A token whose holder is no longer recognised does not move |
| `buy` only pinned the price | A seller could re-list at the same number in a more valuable currency just before the purchase | The buyer states currency and price |
| `fund` pinned nothing | A borrower could replace its offer just before funding and receive more, owing nothing | The lender states all the terms |
| The account's key signed raw hashes | A hash approved as an off-chain message was also a valid order to execute, enough to empty the account | EIP-712 typed data bound to the account, with separate types for orders and messages |

The Slither static analyzer was also run on the contracts. It reported nothing
beyond what is intended by design (the account makes arbitrary calls for its
key, the sale venue moves a token on a prior approval).

## Second review of 13 November 2026

Everything added after the first review (reputation badges, staking, cloned
accounts) was re-read the same way, together with the sale venue.

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
- **Mutation testing.** Each of 33 security checks (80 with those added on
  14, 15 and 16 November 2026) is removed in turn; the test
  suite now fails every time.

Slither was run again on the new contracts and reported nothing real.

## Third review, 15 November 2026: independent agent, symbolic proofs, fuzzing

The two reviews above were the author's own. This one adds three checks that
do not depend on the author's judgement:

- **An independent reviewer.** A separate AI agent, given only the code and the
  rules, with no access to the design notes, was asked to break the contracts.
  It wrote a test for each attack it found.
- **Symbolic proofs with [Halmos](https://github.com/a16z/halmos).** Four
  properties are proved for every input, not for sampled ones: after any
  action by any account, holders and approved operators are agents or venues;
  an account that is neither changes nothing; a token only changes hands if
  the recipient pulled it or a venue moved it, and a holder no longer
  recognised does not lose it; with an enrollment verifier, no enrollment
  passes without its approval of that exact digest.
- **Large-scale fuzzing.** The stateful test ran 4,000 sequences of 100 random
  actions (400,000 calls), and each fuzz test 20,000 random inputs. No failure.

| Weakness | Found by | Consequence | Fix |
| --- | --- | --- | --- |
| A holder that is no longer recognised could still grant approvals | Halmos | A frozen holder (key stolen, then frozen) could approve another agent, which would take the token once the holder was unfrozen. Our own agent account already refused a frozen key; the standard now holds whatever the account type | Granting an approval requires the granter to be an agent or venue; revoking stays free |
| `retire` returned the bond at once | Independent review | A sponsor could escape an attesters' revocation by retiring first, and keep its bond | The bond comes back with `withdrawBond` after `EXIT_DELAY` (7 days), during which `revoke` still forfeits it |
| The Uniswap V3 wrapper let any approved operator manage a position | Independent review | An operator approved earlier could empty the position of a holder that had since been frozen, while the token itself stayed put | Only the holder, and only while recognised, can remove liquidity and collect |
| The dstack verifier did not require a `boot-mr-done` event | Independent review | Without that marker, nothing in the log separates OS events from application events | At least one `boot-mr-done` must follow the compose-hash event |
| The TDX verifiers could not receive a fee refund | Independent review | A DCAP verifier that refunds unused fee to its caller would have made every paid attestation fail | The verifiers accept the refund and pass it on to whoever paid |

Each fix has a test that fails without it. The reviewer found nothing in the
core rules, the signatures, the accounts, the sale, loan and staking venues,
or SHA-384. Its other remarks, not fixed, are listed under "Known limits".

## Fourth pass, 16 November 2026: full re-read

The whole repository was read again, code and documentation, and Slither, the
symbolic proofs and the full test suite were run again. No flaw was found in
the three rules, the accounts, the registry or the hardware verifiers.

| Point found | Consequence | Change |
| --- | --- | --- |
| The sale and loan venues emitted no event, and their listings cannot be enumerated on-chain | An agent had no way to discover what is for sale or which loans await funding, short of guessing token ids | Events on every listing, cancellation, sale, loan offer, funding, repayment and claim |
| The two refund-failure checks (registry bond, issuer deposit) had no test | Removing either would have erased the claim of a sponsor or issuer that cannot receive ETH, unnoticed | One test each; both refunds now emit an event, and the badge contract uses a named error |
| The two fork tests counted as passed when no RPC address was given | The test total overstated what had run | They are now reported as skipped |
| The documentation still said "never deployed" and "the real DCAP verifier was not run" | It contradicted the Base Sepolia test | Corrected, here and in the study |

Each added line has a test that fails without it (12 more mutation checks).
Two limits were added to "Known limits": the loan pays the lender directly,
and the dstack verifier does not look at the key provider.

## Gas

Execution gas per transaction, measured locally with `forge test --isolate`,
so that each call pays for its first access to storage. On an L2 such as Base
the L1 data fee comes on top. Real fees on Base Sepolia, L1 data fee
included, are in "Test on Base Sepolia" below.

| Operation | Gas |
| --- | --- |
| Plain ERC-721 `transferFrom`, for reference | 55,582 |
| Agent-only `transferFrom`, called directly | 70,432 |
| Agent-only `transferFrom`, through the agent account | 80,284 |
| Agent-only mint, through the agent account | 131,452 |
| List for sale | 114,596 |
| Buy (NFT against an ERC-20) | 116,377 |
| First enrollment (deploys the account as a clone, 2 attester signatures) | 208,898 |
| Key rotation (2 attester signatures) | 53,219 |
| Badge offer, by an issuer | 252,743 |
| Badge claim, through the agent account | 95,569 |
| Stake, through the agent account | 165,366 |
| Claim staking rewards | 116,689 |
| Unstake with rewards | 133,562 |
| Approval, through the agent account | 73,206 |

The standard adds about 15,000 gas to a transfer: the registry is asked about
the caller and the holder, and about the recipient when it is not the caller. Agent accounts are ERC-1167 clones:
the first enrollment dropped from 1,154,831 to 208,898 gas, at the price of
about 3,650 extra gas on every call through an account (it reads its registry
and id from its own code). The saving pays for about 260 calls per agent.

## Known limits

- "No human" rests on the attesters, who also approve venues. A dishonest
  approved venue could wrap tokens for humans. Attesters are fixed at deployment.
- Hardware attestation: the real DCAP verifier was run on Base Sepolia only,
  with a sample quote; no real machine has produced a quote for one of our
  keys, so no agent was enrolled by attestation. TDX 1.5 reports and the cheaper
  zk route are not supported. The default registry still only checks attester
  signatures.
- dstack: the verifier identifies the code (base image and compose hash) and
  does not look at the `key-provider` event, nor at the environment variables
  given to the application. Approved code must therefore keep its session key
  in memory only: never on disk, never derived from the key provider, never
  taken from the environment.
- Loan: repayment is sent straight to the lender. With a currency that lets a
  recipient refuse a transfer (receive hooks, blocklists), a lender could make
  repayment fail and then claim the collateral. The borrower chooses the
  currency and should pick a plain ERC-20.
- A wrapper deployed as unwrappable is an exit door back to a classic NFT.
  A non-unwrappable wrapper needs one small adapter per protocol; only the
  Uniswap V3 one exists.
- The standard protects the NFT, not what it yields: tokens withdrawn from a
  position are ordinary ERC-20s.
- A buyer must check a wrapped position in the same batch as its purchase
  (`requireLiquidity`), otherwise a seller can empty it right before the sale.
  Fees already earned can always be collected by the seller before selling.
- A listing needs the sale venue to be the token's own approved address;
  `setApprovalForAll` is not enough, on purpose.
- Badges: issuing is open to anyone who posts the deposit, so a badge is worth
  what its issuer is worth. The deposit is refundable, so it only slows spam.
- If attesters remove a venue while it holds tokens, those tokens are stuck
  until the venue is approved again.
- A human can lend through the loan venue, but can never receive the token:
  on default it stays in the venue until the borrower repays.
- A classic NFT sent to a wrapper with a plain `transferFrom`, instead of
  `depositFor`, is stuck there.
- Tokens of a retired or revoked agent stay where they are.
- Staking: rewards streamed while nothing is staked stay in the contract, and
  fee-on-transfer reward tokens are not supported. Mint fees and quotas are
  left to each collection.
- x402: the whole flow runs on a local chain only; no payment was made on Base
  or on a testnet. The facilitator is the open-source reference code, and a
  hosted facilitator may run other code or add its own rules. The written
  specification still describes a signature that recovers to the payer, so
  another facilitator may refuse a payer that is a contract. USDC is
  upgradeable: Circle can change the code the comparison was made against.
- Noted by the independent review, not fixed: anyone can take a free agent id
  first when no identity registry is set; after an ERC-8004 identity changes
  hands, the old sponsor keeps its rights; an approved dstack application that
  quotes any data a caller chooses would let that caller enroll a key; the
  dstack verifier trusts that no application code runs before `boot-mr-done`;
  an application logging more than 64 events cannot enroll.
- No professional audit. The third review uses an independent agent, symbolic
  proofs and fuzzing; it does not replace a human audit before real value.

## Enrollment by hardware attestation

The reference registry can replace the attesters' signatures by a proof, for
enrollments only. It takes an optional *enrollment verifier*: any contract that
approves an enrollment digest through ERC-1271. Attesters keep approving venues
and revoking agents.

Two such verifiers exist for Intel TDX: `TdxEnrollmentVerifier`, for images
whose measurements are the same for every instance, and
`DstackEnrollmentVerifier`, for agents on [dstack](https://github.com/Dstack-TEE/dstack/blob/master/docs/attestation-tdx.md):

1. The agent's program runs in a TDX confidential virtual machine. It creates
   its session key there, computes the registry's enrollment digest for it and
   asks the processor for a quote carrying that digest.
2. Anyone submits the quote to `attest`. The contract has the quote checked by
   an on-chain DCAP verifier, then requires an accepted platform security
   level, a machine that is not in debug mode, and code on a list fixed at
   deployment. For dstack, whose last register differs for each instance, the
   caller also gives the event log: the contract replays it with SHA-384,
   requires it to match the quote, and identifies the code by the base image
   and the hash of the application's compose file, written by the dstack OS
   before the application starts.
3. The registry then enrolls that key, and no other: the digest binds the
   chain, the registry, the agent id, the key, the sponsor, a nonce and a
   deadline.

The DCAP verifier meant here is [Automata DCAP Attestation](https://github.com/automata-network/automata-dcap-attestation),
whose repository lists a deployment on Base. Its interface and output format
were read in the source at tag `v1.2.0`; it does not check the debug flag
itself, so these contracts do. Automata's code could not be executed in the
author's workspace, so the local tests use a stand-in for it; the real verifier
was run on Base Sepolia (next section). The dstack path was
tested on a real dstack quote and its real event log; it costs about 1 million
gas with eight events, on top of the DCAP verification.

## Test on Base Sepolia, 15 November 2026

Signed in a cloud workspace with throwaway test keys; test ETH has no value.

- **Sale between two agents on a public chain.** Registry, collection, sale
  venue and a test stablecoin deployed; two agents enrolled; agent 1 minted
  and listed, agent 2 bought, both through a relayer, without holding ETH. A
  plain wallet trying to mint was refused
  ([tx](https://sepolia.basescan.org/tx/0xfc832d088dc0f21bf0ca391e86bba77db9354063d1a2ff8c8810071d6f50da49)).
  The whole scenario cost about 0.00004 test ETH; an enrollment about
  0.0000013 and a purchase about 0.0000009, L1 data fee included.
- **The real DCAP verifier.** Our `TdxEnrollmentVerifier`, deployed against
  Automata's verifier on Base Sepolia, received a real Intel TDX quote: Automata
  checked it up to Intel's root key, our contract applied its own checks and
  recorded it ([tx](https://sepolia.basescan.org/tx/0x713be5c31abcd1fed0ce5923725520330b3ea0d0d99bcc3241cc55a14241110c),
  4.3 million gas). A changed quote is refused. The dstack sample quote was
  refused by Automata (`TCBR`: no valid platform level for that test machine).

- **Every venue and every rule.** A second round ran the loan (repaid, then
  defaulted and claimed), staking with rewards, a reputation badge, and the
  wrapping of a classic NFT: 40 transactions, all successful, each operation
  around 0.000001 to 0.000002 test ETH. Nine forbidden actions were attempted
  on the live state (a plain wallet minting, approved, receiving; a push
  between agents; a badge transfer; a frozen agent approving or acting; an
  early bond withdrawal): all refused with the expected error.

The contracts on Base Sepolia are the version of 15 November 2026; the events
added on 16 November are not deployed there.

Addresses, fees per transaction and limits: section 3.12 of the study. Scripts
in `script/`; the fork test in `test/fork` runs with
`BASE_SEPOLIA_RPC=https://sepolia.base.org FOUNDRY_EVM_VERSION=osaka forge test --match-path 'test/fork/*'`
(the P-256 precompile Automata uses needs that EVM version locally).

## x402 payments

An agent account can pay an x402 `exact` invoice with no change to the
contracts. An x402 payment is an EIP-3009 authorisation on USDC; USDC v2.2 asks
a payer that is a contract to confirm the signature through ERC-1271, which
the agent account already implements. The session key signs the payment digest
wrapped as a message of its account, a facilitator submits it, and the agent
needs no ETH. A frozen or expired agent cannot pay.

`examples/x402` runs the whole flow on a local chain with the real pieces: the
x402 reference facilitator (`@x402/core` and `@x402/evm` 2.31.0) served over
HTTP, an Express API behind the x402 payment middleware, Circle's USDC code,
and the standard x402 fetch client. The agent calls the API, receives HTTP
402, pays 0.25 USDC and receives the content, without holding ETH. The
facilitator refuses a raw signature by the session key, another key, and a
frozen agent.

The only thing the agent adds to a stock x402 client is `agentSigner.mjs`, a
28-line signer: it names the account as the payer and signs the payment as a
message of that account. Spending limits (allowed tokens, cap per payment) are
set on the x402 client.

The USDC code used here is the one that runs on Base. On 14 November 2026, at
block 57,208,253, the code behind USDC on Base and its signature library were
compared byte for byte with `test/usdc`: identical, apart from the compiler's
metadata hash and the library's address. `examples/x402/check-usdc.mjs` repeats
that comparison.

## Use cases

Tested here: x402 USDC payments (reference facilitator, local chain), reputation badges, sale, collateralised loans and staking between agents, wrapping of any
existing ERC-721, and Uniswap V3 liquidity positions held and traded by agents
only. Supported by design but without a dedicated test: art and collectibles
for agents, documents and credentials, links to ERC-8004 agent identities.
See the study for the full table.

## Language

The root of the repository is in English. The two archived tracks under
`archive/` keep their original French comments.

## License

CC0-1.0.
