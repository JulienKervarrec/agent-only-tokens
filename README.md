# Agent-Only Tokens

[![tests](https://github.com/JulienKervarrec/agent-only-tokens/actions/workflows/test.yml/badge.svg)](https://github.com/JulienKervarrec/agent-only-tokens/actions/workflows/test.yml)

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
| `src/IAgentRegistry.sol` | The two questions asked to a registry | <!--f:lines.IAgentRegistry-->10<!--/f--> |
| `src/IERC721AgentOnly.sol` | The interface a compliant token exposes, advertised through ERC-165 | <!--f:lines.IERC721AgentOnly-->10<!--/f--> |
| `src/ERC721AgentOnly.sol` | The standard: the three rules | <!--f:lines.ERC721AgentOnly-->70<!--/f--> |
| `src/AgentAccount.sol` | An agent's account, with no human owner, driven by a rotating session key. Single calls, batches, relayed calls, ERC-1271. Each account is an ERC-1167 clone of one implementation | <!--f:lines.AgentAccount-->139<!--/f--> |
| `src/AttestedAgentRegistry.sol` | Reference registry: k-of-n attesters, each a key or a contract such as a multi-signature wallet, who can hand over to another set, refundable bond, expiring keys, optional ERC-8004 identity link, optional enrollment verifier that the attesters can replace, bond returned after an exit delay. Decisions that widen what it accepts (a venue, a verifier) or change who decides (the attesters) wait for a notice delay; removals and the enrollment halt are immediate; every decision carries a deadline | <!--f:lines.AttestedAgentRegistry-->525<!--/f--> |
| `src/experimental/TdxQuoteVerifier.sol` | Checks shared by the hardware verifiers: the quote is checked by an on-chain DCAP verifier (Automata's interface), accepted platform level, no debug mode, report data holding the digest only | <!--f:lines.TdxQuoteVerifier-->116<!--/f--> |
| `src/experimental/TdxEnrollmentVerifier.sol` | Enrollment verifier for TDX images whose measurements are the same for every instance | <!--f:lines.TdxEnrollmentVerifier-->41<!--/f--> |
| `src/experimental/DstackEnrollmentVerifier.sol` | Enrollment verifier for agents on dstack: replays the RTMR3 event log and identifies the code by its base image and compose hash | <!--f:lines.DstackEnrollmentVerifier-->138<!--/f--> |
| `src/experimental/Sha384.sol` | SHA-384, needed to replay TDX registers; the EVM has no precompile for it | <!--f:lines.Sha384-->92<!--/f--> |
| `src/experimental/DstackConfigIdVerifier.sol` | Simpler enrollment verifier for agents on dstack: reads the compose hash in the quote itself (`MRCONFIGID`), with no event log and no SHA-384 | <!--f:lines.DstackConfigIdVerifier-->64<!--/f--> |
| `src/AgentSwap.sol` | Fixed-price sale between agents; events announce each listing and sale | <!--f:lines.AgentSwap-->64<!--/f--> |
| `src/AgentLoan.sol` | Collateralised loan between agents; repayments wait in the venue for the lender; events announce each offer and each step | <!--f:lines.AgentLoan-->116<!--/f--> |
| `src/AgentStaking.sol` | Staking of agent-only NFTs for ERC-20 rewards (Synthetix-style accounting, one NFT = one unit) | <!--f:lines.AgentStaking-->130<!--/f--> |
| `src/AgentWrapped721.sol` | Wrapper that makes any existing ERC-721 agent-only | <!--f:lines.AgentWrapped721-->80<!--/f--> |
| `src/AgentWrappedUniV3.sol` | Non-unwrappable wrapper for Uniswap V3 liquidity positions | <!--f:lines.AgentWrappedUniV3-->98<!--/f--> |
| `src/AgentReputationBadge.sol` | Reputation badges: agent-only and soulbound (ERC-5192). An issuer offers, the agent claims; issuers post a refundable deposit and have a daily quota | <!--f:lines.AgentReputationBadge-->218<!--/f--> |
| `examples/enclave-agent/` | The three agent programs that ran in real TDX machines, the quotes they produced, and the record of the runs: the first enrollment by hardware attestation, then an enclave agent paying by x402. `manifest/` rebuilds the manifest dstack measures, so each program's compose hash can be recomputed | |
| `.github/workflows/` | `test.yml`, on every push: tests, gas against `snapshots/Gas.json`, figures of this documentation, symbolic proofs, Slither. `nightly.yml`: the tests against Base Sepolia and the code at every recorded address. `weekly.yml`: mutation testing | |
| `tools/` | `mutate.py` (mutation testing), `figures.py` (figures quoted in the documentation), `deployments.py` (addresses), `slither_check.py` (Slither against the accepted findings) | |
| `deployments/base-sepolia.json` | Every contract deployed for the tests on Base Sepolia: address, role, block, code hash, the commit that compiles to it and its Sourcify result | |
| `snapshots/Gas.json` | Gas of each operation of the gas table, written by `test/Gas.t.sol` | |
| `SECURITY.md`, `CONTRIBUTING.md`, `CITATION.cff` | How to report a weakness, the rules a change must meet, how to cite | |
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

Mutation testing breaks each security check in turn and requires the tests to
notice (about half an hour); `CONTRIBUTING.md` lists the other checks:

    python3 tools/mutate.py

The hardware verifiers and SHA-384 are newer and less reviewed than the
standard; they live in `src/experimental`, with their tests and fixtures in
`test/experimental`. Nothing in the standard depends on them.

<!--f:tests-->208<!--/f--> tests run locally; <!--f:tests.fork-->5<!--/f--> more run only against Base
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

<!--f:tests.experimental-->55<!--/f--> tests cover enrollment by hardware attestation and SHA-384 (see
"Enrollment by hardware attestation" below). They use a real Intel TDX quote
(`test/experimental/tdx`), a real dstack quote with its event log
(`test/experimental/dstack`) and four quotes from our own machines
(`test/experimental/phala`). In these local tests a stand-in replaces the DCAP
verifier. The real one is exercised by three of the fork tests in `test/fork` and
was run on Base Sepolia (see "Test on Base Sepolia" below).

<!--f:tests.Notice-->17<!--/f--> tests cover the notice delay and the enrollment halt (see "Notice
delay and enrollment halt" below), and <!--f:tests.Guards-->21<!--/f--> more were written for the checks
that systematic mutation testing found untested (see "Fifth pass" below).

<!--f:tests.fuzz-->5<!--/f--> tests are fuzzed over 512 random inputs each. One is a stateful invariant
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
  suite now fails every time. Those checks were picked by hand: the fifth
  pass below replaced the list with a systematic one, and found gaps.

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

## Fifth pass, 16 November 2026: systematic mutation testing

Until this pass, mutation testing ran on a list of checks picked by hand, and
that list lived outside the repository. `tools/mutate.py` now builds the list
from the code: it disables every `if (...) revert` guard of `src/` in turn
(each alternative of an `a || b` guard separately), removes every
unconditional revert, and applies the <!--f:mutants.listed-->163<!--/f--> changes written in
`tools/mutations.json` (a state update dropped, a field left out of a signed
digest, a comparison weakened). That makes <!--f:mutants-->300<!--/f--> mutants.

**Result of the first run: 63 mutants went unnoticed.** The sentence "each
added line has a test that fails without it" was true of the hand-picked list
only.

- 61 were checks without a test. None was a flaw: every test written for them
  passed on the unchanged contracts. But any of them could have been removed
  by mistake without a test failing. Among them: only the borrower cancels or
  repays a loan; a funded loan cannot be cancelled; the bond of a live agent
  cannot be withdrawn; only the sponsor freezes or retires its agent; one
  attester does not count twice; a relayed order cannot be sent to another
  target; a revocation signed for one agent does not revoke another.
  <!--f:tests.Guards-->21<!--/f--> tests in `test/Guards.t.sol` now cover them, with three new tests
  and one extended in `test/experimental`.
- 2 cannot change behaviour (a second check already refuses the same case).
  They are listed with the reason in `tools/mutations-accepted.json`.

Every mutant is now caught or explained, and the list is replayed every week.

Slither also joined the automated checks, against a list of accepted findings
with the reason for each (`tools/slither-accepted.json`, <!--f:slither.accepted-->57<!--/f--> names for
<!--f:slither.findings-->59<!--/f--> findings): a new finding fails the check. One trap found on the way: the path filter `test`
also matched `AttestedAgentRegistry.sol` and hid every finding in the
registry; the filter is now `/test/`.

**The deployed code can be read.** <!--f:deployed-->70<!--/f--> contracts were deployed on Base Sepolia
for the tests. <!--f:deployed.clones-->19<!--/f--> are agent accounts, clones of an implementation;
<!--f:deployed.verified-->51<!--/f--> of the others are verified on [Sourcify](https://sourcify.dev): <!--f:deployed.exact-->48<!--/f--> match
their source exactly, <!--f:deployed.match-->3<!--/f--> match on code only (their sources differed by
comments). `deployments/base-sepolia.json` names, for each one, the commit of
this repository that compiles to it. Example: the
[registry of the notice-delay run](https://repo.sourcify.dev/84532/0x6E9b127e0FB218CfD12fE0D45264F7e3D0A58134).

## Sixth pass, 16 November 2026: independent review of the notice delay

The notice delay was handed, before being merged, to a reviewer that had not
seen it being written: an independent agent with the code, the tests and the
tools, asked to break it. **It found no critical or high-severity flaw**, and
thirteen points worth acting on:

| Found | Done |
| --- | --- |
| An announcement named an address, not code: a venue or verifier could be announced empty and receive any code after the notice | An address without code is refused, at deployment too |
| The documentation said the delay binds a dishonest quorum. Not while attesters sign enrollments themselves: they can enroll any key at once | Written as a limit, here and in the study |
| No test halted a verifier after it had taken over by announcement: a registry that skipped that halt passed every `forge` test | Test added, that broken registry added to the mutants, and the proof of the halt now also checks what the registry reports |
| Replacements and halts shared one counter and never expired: a replacement signed and never sent could be sent first to void a halt just signed, and an unsent halt stayed usable forever | A deadline on both, a counter each, and a halt voids the unsent replacements |
| Nothing tied the delay to the life of a key: with a delay longer than every key, a halt could not be lifted before all agents lost theirs | Refused at deployment |
| "Announcing the verifier in force cancels" is wrong under a halt: it lifts the halt | Documented and tested: under a halt, only another halt cancels |
| After a halt the registry still showed the cancelled verifier; the halt event did not say which verifier was stopped | Cleared; the event names it |
| "About 330 gas" per enrollment only held until the first takeover | Measured in `snapshots/Gas.json` and stated: <!--f:gas.takeover-->2,120<!--/f--> gas more afterwards |
| A halt can cost a borrower its pledged token (its key expires, the loan falls due) | Written as a limit |
| Enrollments signed by attesters before a halt work again once it is lifted, until their deadline | Written as a limit |
| The Slither check compared names only: a second finding under an accepted name passed | Counts per name |
| The mutation tool counted any failure of `forge` as a caught mutant, and named accepted mutants by line number | A mutant is caught only by a failing test; a crash or a timeout fails the run; names carry no line number |
| The proofs were described as covering "every order of two decisions" | Reworded to what they cover |

Left open that day: signatures approving or removing a venue, and revoking
an agent, had no deadline. They have one since 17 November (see
"Replaceable attesters" below).

After the corrections: 223 mutants, all caught or explained; the run on
Base Sepolia of the notice delay was made again on the corrected registry.

## Seventh pass, 17 November 2026: independent review of the handover

The handover was reviewed before publication, the same way as the notice
delay: an independent agent with the code, the tests and the tools, asked to
break it. It wrote 24 tests and 33 broken variants of the new code. **It found
no critical or high-severity flaw**, and nine points worth acting on:

| Found | Done |
| --- | --- |
| 13 of its 33 broken variants passed every test. Two were real breaks that no proof caught either: a set that took over and hands over in turn decided at the previous threshold, and a set number could be reused after two announcements in a row. The code was correct; nothing checked it | A test for each of the 13, and all 13 added to the listed mutants |
| A handover could give the registry, for good, to addresses that nobody holds. The README said a registry could not be left without attesters | The new set must accept: enough of its members to reach its threshold sign the handover |
| Signatures given and never sent were not tied to a set: one old signature became a quorum when the threshold was lowered, and old signatures counted again when their signers returned | Everything the attesters sign now names their set: a handover voids what was signed and not sent. What a hardware verifier approves is unchanged, so the agents' programs are too |
| "Every decision expires" holds only if the signers choose a deadline that is not far away | Reworded: a deadline chosen by its signers |
| The proof was described as covering every decision; it checks a halt, with sets of one member | Reworded |
| Eight sentences were wrong, stale, or true only under a condition left unsaid | Corrected |
| Nothing kept "five" and "twelve" broken registries true | `tools/proofs.py`, run every week |
| With keys that barely outlive the notice delay, a halt followed by a handover can outlast every key | Written as a limit |
| A revocation has a deadline but no counter: unsent, it cannot be withdrawn before its deadline | Written as a limit |

The reviewer also read the prover's source and confirmed both claims made
about it above, and that the form of what attesters sign matches an
independent EIP-712 library.

## Eighth pass, 17 November 2026: independent review of contract attesters

The attesters that are contracts were reviewed before publication, the same
way: an independent agent with the code, the tests and the tools, asked to
break the change and to check the documentation against the code. It wrote
49 tests, 7 of them against the real Safe contracts on a fork, and 34 broken
variants of the new code.

**It found no critical, high or medium flaw**, one design risk of low
severity, and nine other points worth acting on.

| Found | Done |
| --- | --- |
| A key attester whose account delegates to code (EIP-7702) could be named as a contract: that code then signed alone, without the key. One authorization signed by that key for any purpose gave its seat to whatever that code accepts | The registry no longer asks such an account as a contract: it signs by its key only. Checked with a real delegation, in a test and on Base Sepolia |
| 16 of the reviewer's 34 broken variants passed every test. Three mattered: one address counted twice when it signed in both forms, a wallet counted twice around another member, a member asked by a call that lets it change the registry. The code was right, but nothing checked it | A test for each of 11; 7 are now listed mutants. Four are left without a test, by choice: a cap on the gas given to a member, and three about encodings accepted or refused without consequence. One is an equivalent change |
| A contract asked to accept a handover no longer saw the digest it was asked about: the counter had already moved | The counter now moves after the new set is asked |
| "A wallet can take back what it accepted" is false for what a Safe approved on chain: that approval outlives its owners | Reworded, with a test on the real Safe |
| "The new set must accept, so a registry is not handed to keys that nobody holds" holds for keys only: a contract accepts by answering yes once | Reworded here and in the code's comments, with a test |
| The threshold counts addresses, not people: a wallet and one of its owners are two members | Written as a limit, with a test |
| A member is given all the gas left and its whole answer is copied: an answer of one megabyte costs about 4 million gas. Only the sender pays, and a contract that is not a member is never called | Written as a limit |
| How malformed signatures are refused was described wrongly, and the encoding was called "standard" although other encodings that decode are accepted | Reworded; the test now asserts each case |
| The 73,000 gas of the fork test was measured with accounts already loaded | Replaced by the gas of the real transactions |
| Four tests proved less than their names: adjacent repeats only, one form of a key's signature only, any revert accepted | Strengthened |

The reviewer also checked that a failed signature recovery always yields the
zero address, which is never a member, so that the explicit error test removed
with this change was redundant; and that the code deployed for the first run
of the day is the code of the repository.

After the corrections: 207 tests and 5 more on a fork, 8 proofs checked against 12 broken
registries, 295 mutants all caught or explained; the run on Base Sepolia was made again
on the corrected registry.

## Gas

Execution gas per transaction, measured by `test/Gas.t.sol` with
`forge test --isolate`, so that each call pays for its first access to
storage. The figures are kept in `snapshots/Gas.json`, and the automated
checks fail when a change moves one of them. On an L2 such as Base
the L1 data fee comes on top. Real fees on Base Sepolia, L1 data fee
included, are in "Test on Base Sepolia" below.

| Operation | Gas |
| --- | --- |
| Plain ERC-721 `transferFrom`, for reference | <!--f:gas.01-->55,162<!--/f--> |
| Agent-only `transferFrom`, called directly | <!--f:gas.02-->70,362<!--/f--> |
| Agent-only `transferFrom`, through the agent account | <!--f:gas.03-->80,193<!--/f--> |
| Agent-only mint, through the agent account | <!--f:gas.04-->131,409<!--/f--> |
| List for sale | <!--f:gas.05-->114,575<!--/f--> |
| Buy (NFT against an ERC-20) | <!--f:gas.06-->116,392<!--/f--> |
| First enrollment (deploys the account as a clone, 2 attester signatures) | <!--f:gas.07-->214,549<!--/f--> |
| Key rotation (2 attester signatures) | <!--f:gas.08-->58,858<!--/f--> |
| Badge offer, by an issuer | <!--f:gas.09-->252,996<!--/f--> |
| Badge claim, through the agent account | <!--f:gas.10-->95,526<!--/f--> |
| Stake, through the agent account | <!--f:gas.11-->165,384<!--/f--> |
| Claim staking rewards | <!--f:gas.12-->116,668<!--/f--> |
| Unstake with rewards | <!--f:gas.13-->133,594<!--/f--> |
| Approval, through the agent account | <!--f:gas.14-->72,826<!--/f--> |
| Key rotation once an announced verifier has taken over | <!--f:gas.15-->60,978<!--/f--> |
| Attesters hand over to a set of three (2 signatures) | <!--f:gas.16-->158,273<!--/f--> |
| Venue approval signed by two keys | <!--f:gas.17-->93,008<!--/f--> |
| Venue approval signed by a key and a wallet of two owners | <!--f:gas.18-->109,032<!--/f--> |

The standard adds about 15,000 gas to a transfer: the registry is asked about
the caller and the holder, and about the recipient when it is not the caller. Agent accounts are ERC-1167 clones:
the first enrollment dropped from 1,154,831 to <!--f:gas.07-->214,549<!--/f--> gas, at the price of
about 3,650 extra gas on every call through an account (it reads its registry
and id from its own code). The saving pays for about 260 calls per agent.

## Known limits

- "No human" rests on the attesters, who also approve venues. A dishonest
  approved venue could wrap tokens for humans.
  Since 16 November 2026 an approval takes effect only after a notice delay
  fixed at deployment, so that holders see it coming; the delay gives time to
  leave, it does not stop dishonest attesters.
- Since 17 November 2026 the attesters can hand over to another set of
  attesters, after the same notice delay. A lost or stolen key can be replaced
  while the remaining members still reach the threshold; a dishonest quorum
  can also hand the registry to anyone, which holders see coming. The new set
  must sign its own appointment, so a registry is not handed by mistake to
  keys that nobody holds. Nothing can remove an attester faster than the delay.
- The deadline of a decision is chosen by its signers, and nothing caps it.
  Until that deadline, or until another set of attesters is in force, a
  signature given and not sent can be sent by anyone. A revocation has no
  counter: it cannot be withdrawn earlier.
- Two notices in a row (a halt, a handover, then the lift by the new set) can
  last longer than a key if keys barely outlive the notice delay. Keys should
  live several notice delays.
- An attester that is a contract decides whatever its code accepts. A wallet
  whose owners can be changed, or a contract that can be upgraded, changes
  who decides without a handover and without the notice delay. It accepts its
  appointment by answering yes once, which does not show that someone
  controls it; and the threshold counts addresses, not people.
- The notice delay does not cover enrollments that attesters sign themselves,
  which is the default: a dishonest quorum can enroll a human's key at once.
  It binds a quorum for venues, for the verifier and for the attesters
  themselves, not for enrollments.
- An announcement commits to an address that holds code, not to what that code
  does later: a venue or verifier written as a proxy can still change. The
  notice is the time to read the code, and to refuse to use one that can.
- Hardware attestation: three agents were enrolled by attestation, on Base
  Sepolia, from two machines of one provider (see "First agent enrolled by
  hardware attestation" and "An enclave agent pays by x402"). Their base image
  is exactly the one dstack published for that version (see "The base image
  checked"), but it was not rebuilt from source. TDX 1.5 reports and the cheaper zk
  route are not supported. The default registry still only checks attester
  signatures.
- The manifest dstack hashes includes a pre-launch script. The provider's
  default one adds to root's authorized keys the SSH keys listed in a file
  that the host supplies and dstack does not measure; the approved base image
  starts no SSH server and no console login, so those keys open nothing (see
  "The base image checked"). Since 17 November our agent runs a script of
  our own that does nothing (see "Our own pre-launch script"). What an
  application's own compose starts remains its own concern.
- The attesters can replace the enrollment verifier. That is how a program is
  upgraded, and it has a price: the hardware proof binds a registry only as
  long as its attesters keep a verifier that demands it. Two of three could
  install one that accepts anything, as they could already approve a venue
  that hands tokens to humans. Each replacement emits an event and, since
  16 November 2026, waits for the notice delay (see "Notice delay and
  enrollment halt"). A registry deployed with a delay of 0 has no such
  protection: `noticeDelay` is public, a collection should read it.
- A halt stops key rotations too. A halt that lasts longer than a key's
  remaining life leaves that agent without a key until enrollments resume. Its
  tokens stay in its account, but what needs the agent to act in time is lost:
  a borrower that cannot repay loses the token it pledged.
- Enrollments that attesters signed before a halt work again once the halt is
  lifted in favour of signed enrollments, until their deadline, if their
  signers are still attesters.
- `DstackConfigIdVerifier` rests on one more behaviour of the base image than
  the event-log verifier: the dstack OS must refuse to boot when `MRCONFIGID`
  does not match the manifest it loads. That check was read in dstack's source,
  not provoked on a machine.
- dstack: the verifiers identify the code (base image and compose hash). They
  do not look at the environment variables given to the application, and at
  the key provider only when the approved `MRCONFIGID` is in format 2 or 3,
  which Phala Cloud does not write (study, section 3.22). Approved code must therefore keep its session key
  in memory only: never on disk, never derived from the key provider, never
  taken from the environment.
- Loan: a currency that takes a fee on transfers is not supported: the venue
  would owe lenders more than it holds.
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
- x402: payments were made on a local chain and on Base Sepolia, never on a
  main network. On Base Sepolia the facilitator was the hosted test one of
  x402.org and the shop its demonstration page. A production facilitator may
  run other code or add its own rules. The written specification still
  describes a signature that recovers to the payer, so another facilitator may
  refuse a payer that is a contract. USDC is upgradeable: Circle can change
  the code the comparison was made against.
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

Three such verifiers exist for Intel TDX: `TdxEnrollmentVerifier`, for images
whose measurements are the same for every instance, and two for agents on
[dstack](https://github.com/Dstack-TEE/dstack/blob/master/docs/attestation-tdx.md),
`DstackEnrollmentVerifier` and the simpler `DstackConfigIdVerifier`:

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

`DstackConfigIdVerifier` needs the quote alone. Since version 0.5.1, dstack
also writes the compose hash into a field of the quote that the processor
signs (`MRCONFIGID`), and its OS [refuses to boot](https://github.com/Dstack-TEE/dstack/blob/350a0a73ffdb6041bda69118f13d81591870b565/dstack/dstack-util/src/system_setup/config_id_verifier.rs)
when that field does not match the manifest it loads. The contract hashes that
field together with the boot measurements: one identity for the base image and
the application. On Base Sepolia it cost 3,719,444 gas against 4,777,969 for
the event-log route, DCAP verification included; without it, 68,086 gas
against 1,111,564. Since 17 November it also accepts the two other formats
dstack defines for that field, which add the application id and the key
provider: the whole field is part of the approved identity, so a format cannot
let through a program the attesters did not approve (study, section 3.22).

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

The contracts on Base Sepolia are the version of 15 November 2026: the events,
the loan withdrawal and the verifier replacement added on 16 November are not
in those deployments. The registry of "Upgrading an agent's program" below is
the current one.

Addresses, fees per transaction and limits: section 3.12 of the study. Scripts
in `script/`; the fork test in `test/fork` runs with
`BASE_SEPOLIA_RPC=https://sepolia.base.org FOUNDRY_EVM_VERSION=osaka forge test --match-path 'test/fork/*'`
(the P-256 precompile Automata uses needs that EVM version locally).

## First agent enrolled by hardware attestation, 16 November 2026

A real machine produced a quote for one of our keys, and the chain accepted it.

- **The agent.** A 149-line program with no dependency
  (`examples/enclave-agent`) ran in an Intel TDX confidential VM on Phala
  Cloud (dstack 0.5.12, production image). It created its session key in
  memory and asked the processor for a quote over its own enrollment digest.
- **The proof.** On Base Sepolia, Automata's DCAP verifier found the quote
  genuine and the platform up to date. `DstackEnrollmentVerifier` replayed the
  machine's ten RTMR3 events, recognised the approved code and recorded the
  digest ([tx](https://sepolia.basescan.org/tx/0x3bde5e7d3ccf206d60290a8b9de98ae72ea5d79f2fc6368141c3e652613b9fcf),
  4.78 million gas). The registry then enrolled the key with no attester
  signature ([tx](https://sepolia.basescan.org/tx/0x2001f551c48d9b8b279bcfd5a4347bce5a2b1e6dabf4e1c748e8ea719ffeeca2)).
- **The agent acts.** It signed a mint order, a relayer sent it, and the
  agent's account holds the token
  ([tx](https://sepolia.basescan.org/tx/0x28c4cf5995942e47404d73444b91c485b5045189c9124986e972cc5cbe880c64)).
  Neither the account nor the key ever held ETH.
- **Rotation and emergency stop.** After a restart the machine had a new key;
  a new quote rotated it on chain. Frozen by its sponsor, the agent's fresh
  order was refused, then accepted once unfrozen.
- **A modified build is refused.** The same machine running a changed program
  still gets a genuine quote from Intel, and our verifier refuses it:
  `UnknownCode`, or `BadEventLog` if it lies about its compose hash.

Addresses, every step and the limits of this run: `examples/enclave-agent`
and section 3.13 of the study.

## Upgrading an agent's program, 16 November 2026

A verifier approves a fixed list of programs, so a corrected program used to
mean a new verifier, a new registry and a new account. The registry now lets
its attesters replace the enrollment verifier, with the signatures they
already use to approve venues (`setEnrollmentVerifier`).

- **What stays.** The agent's id, its account, its tokens, and its current
  key until it expires or is replaced.
- **What changes.** The next key must satisfy the new verifier. Programs the
  new verifier does not list die out within one key lifetime.
- **Who decides.** The attesters, not the sponsor: a sponsor allowed to approve
  code could approve a program that hands it the key.
- **Verifiers stay immutable.** Each one is a fixed statement of what it
  accepts. Replacing the verifier also covers a new DCAP verifier, another
  platform policy or a zk route.

Run on Base Sepolia with the machine of the previous sections:

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
block earlier; the other steps are transactions. Section 3.16 of the study.
That registry predates the notice delay: there the replacement took effect at
once.

## Notice delay and enrollment halt, 16 November 2026

Until this change the attesters' decisions took effect in the transaction that
carried them. Two of three attesters could approve a venue, or a verifier that
accepts anything, and use it in the same block.

- **A decision that widens waits.** Approving a venue or replacing the
  enrollment verifier is an announcement: it takes effect `noticeDelay` seconds
  later. The delay is fixed at deployment, public, and shorter than the life of
  a key. Until then the venue is a stranger to every token, and the verifier in
  force stays in force.
- **What is announced must hold code.** The notice is there for the code to be
  read: an address without code is refused, for a venue as for a verifier.
- **A decision that narrows is immediate.** Removing a venue, revoking an
  agent, and a new one: `haltEnrollments`, which stops every enrollment and key
  rotation at once, for the day a verifier turns out to accept too much.
- **Cancelling.** Removing a venue cancels its pending approval. A new
  announcement replaces the pending verifier. A halt cancels it, and under a
  halt only another halt does: any announcement that reaches its date lifts
  the halt.
- **Lifting a halt is a widening**: enrollments resume when a verifier
  announced after the halt takes over, one notice delay later. Agents keep
  acting with their current key in the meantime.
- **Signatures on the verifier expire.** A replacement and a halt each carry a
  deadline and their own counter, and a halt voids a replacement signed
  earlier and never sent.
- **No extra transaction.** The registry stores the date and compares it with
  the block time when asked: one storage read per enrollment. Once an
  announced verifier has taken over, every enrollment reads one more slot:
  <!--f:gas.takeover-->2,120<!--/f--> gas more, for good.

**What the delay does not cover.** While attesters sign enrollments
themselves (the default), a dishonest quorum can enroll any key at once: the
delay binds it for venues, for the verifier and, since 17 November, for the
attesters themselves, not for enrollments. With a hardware verifier
in force, going back to signed enrollments is an announcement and waits.

<!--f:proofs.notice-->3<!--/f--> symbolic proofs cover it for every delay and every time, over two
decisions in a row: a venue approved or removed twice is in force only once
its notice has passed since the approval that still stands; after a
replacement or a halt, then a replacement, what was in force stays in force
until the notice has passed; after an announcement then a halt, no enrollment
passes. Each proof fails when the matching rule is broken on purpose. The
repository holds <!--f:proofs-->8<!--/f--> symbolic proofs.

Run on Base Sepolia with a notice delay of 120 seconds, registry
[`0x6E9b…8134`](https://sepolia.basescan.org/address/0x6E9b127e0FB218CfD12fE0D45264F7e3D0A58134),
sale venue [`0x50F0…A25b`](https://sepolia.basescan.org/address/0x50F0a4Fb4747E045EDB3440A7E92931EC8c7A25b):

| Step | Result |
| --- | --- |
| Two attesters approve a venue at an address without code | Refused (`BadInput`) |
| Two attesters approve the sale venue ([tx](https://sepolia.basescan.org/tx/0xa244d7ef1085013ab81c21206122d47520d694d684a13980f0bcdfd6c39d1251)) and announce a hardware verifier ([tx](https://sepolia.basescan.org/tx/0xa953c76f007893e5b4a0951fe9f560e91d1859d8fd184c1062941fc19ceee057)) | 89,316 and 111,573 gas. `isVenue` is false, `enrollmentVerifier` unchanged |
| During the notice, the agent approves the venue for its token | Refused (`NotAgent`) |
| During the notice, a second agent is enrolled by two attesters ([tx](https://sepolia.basescan.org/tx/0xdd3161fe055a06330697f947da4ab1d58c845186798006314a0bde0530fa3123)) | Accepted: the rule in force still applies |
| 120 seconds later | `isVenue` is true, `enrollmentVerifier` is the new verifier, with no transaction |
| The agent approves the venue and lists its token ([tx](https://sepolia.basescan.org/tx/0xa50291dd6c0066c4d9dfdd34d2e093fa7cbd0d00a8a70920b88b36b72deada55), [tx](https://sepolia.basescan.org/tx/0xe91a7ee9d15a608aa43ca88fe9456958c363ec8325fe5e5a377b362c51d11722)) | Accepted |
| A key rotation signed by the attesters | Refused (`NotVerified`): the new verifier decides alone |
| A halt whose signatures have expired | Refused (`Expired`) |
| Two attesters halt enrollments ([tx](https://sepolia.basescan.org/tx/0xe0e3f2566821d25a0eed46d8ab0258db126b9889de582db6ee3c527be04e6bb0)) | 73,858 gas. A key rotation is refused (`Halted`) |
| While halted, the second agent buys the token ([tx](https://sepolia.basescan.org/tx/0x6fd0aa47d12e74fee0699d1605979351292a7b06e974189d99dffce8a217a9cf)) | Accepted: agents keep their current key |
| Two attesters announce that attesters sign enrollments again ([tx](https://sepolia.basescan.org/tx/0xe71ac4d7a836c18fa96b052d22ae1d4605c4290b3c06da67e3f4b943c2e596d8)) | Still halted during the notice (`Halted`) |
| 120 seconds later, the second agent gets a new key ([tx](https://sepolia.basescan.org/tx/0x3275cd635da6e7474bddf3370a885239a78a3aecf7eff7bc64306b3d2d63bcea)) | Accepted. The halt signatures sent again are refused (`BadAttester`) |

The refusals were simulated on the chain's state at that moment; the other
steps are transactions. This run replays, on the registry corrected after the
review below, a first run made the same day on registry
[`0x75Fd…BfcA`](https://sepolia.basescan.org/address/0x75Fd5D6Ce8384c864FefE7bf8990c2AAe070BfcA). Section 3.17 of the study.

## Replaceable attesters, and a deadline on every decision, 17 November 2026

Until this change the attesters were fixed at deployment: a lost key could not
be replaced, a compromised one could not be removed, and a registry lived and
died with its first three keys.

- **A handover.** The attesters in force sign the next set of attesters and
  its threshold (`setAttesters`): to replace a member, to add or remove one, or
  to change how many must sign.
- **The new set accepts.** Enough of its members to reach its threshold sign
  the same handover. A registry cannot be handed by mistake to keys that
  nobody holds.
- **It waits for the notice delay**, like everything that widens: until then
  the set in force keeps deciding and the new one decides nothing. The new set
  takes over on the date, with no transaction.
- **Cancelling.** A new announcement replaces the pending one: announcing the
  set in force again cancels it.
- **What was decided stays decided.** Agents, venues, the verifier, a halt: a
  handover touches none of them. A venue approval still in its notice takes
  effect on its own date.
- **A handover voids what was signed and not sent.** Everything the attesters
  sign names their set. Once another set is in force, a signature given
  before is void, even from a member who stays.
- **Every decision of the attesters now carries a deadline**, chosen by its
  signers: venue approvals and removals, revocations and handovers, as
  enrollments, verifier replacements and halts already did.

**What it does not give.**

- There is no fast path: removing an attester takes the delay too. Below the
  threshold a stolen key decides nothing alone; at the threshold the thieves
  hold the registry and can announce their own set. The delay lets holders see
  it and leave, as for venues.
- A key can be replaced only while the members who remain still reach the
  threshold. With three of three, one lost key freezes the registry.
- An attester was still a plain key: it can be a contract since the next
  section.

**Cost.** Each check of the attesters' signatures reads one more storage slot,
and what they sign has one more field: about 3,200 gas more per enrollment
when the change was made. A first
enrollment costs <!--f:gas.07-->214,549<!--/f--> gas. A handover to a set of three costs
<!--f:gas.16-->158,273<!--/f--> gas.

One symbolic proof covers it for every delay and every time, with sets of one
member: one attester hands over to a second, then whoever is in force hands
over to a third; at any later time the registry names exactly one of the
three, the third once its notice has passed and until then the one in force
when it was announced, and a halt that names the set in force and is signed
by either of the two others is refused. <!--f:tests.Attesters-->16<!--/f--> tests cover what that proof does not: thresholds, sets of
several members, the acceptance, set numbers, deadlines, signatures given
under a previous set, and the exact form of what attesters sign.

What a hardware verifier approves is unchanged: the enrollment alone, without
the attesters' set. The agents' programs, which compute that digest
themselves, need no change.

Each proof of the registry is run against registries broken on purpose, and
must fail on them: <!--f:proofs.broken-->12<!--/f--> broken registries, checked by `tools/proofs.py`
every week.

Writing that proof showed a limit of the prover: halmos 0.3.3 ties a signature
to its signer, and a key to its address, only on the path where it is first
used, so a proof that signs after the paths have split reports failures that
do not exist. The proof makes every signature first. The earlier proofs are
not affected: the gap can only add false alarms, not hide a failure.

Run on Base Sepolia with a notice delay of 120 seconds, registry
[`0xaD00…8587`](https://sepolia.basescan.org/address/0xaD00cF7F3cc559431Ba404993a1B575305378587),
attester keys made for the tests:

| Step | Result |
| --- | --- |
| Agent 1 is enrolled by attesters 1 and 2 ([tx](https://sepolia.basescan.org/tx/0xdc943c0fd5911d4fc25ba89587d7573f7194cc22dd9ff417c2370fdb13541529)) | 214,639 gas |
| A handover, a venue approval and a revocation whose signatures have expired | Refused (`Expired`), all three |
| Attesters 4 and 5, who are not in the set in force, sign a handover | Refused (`BadAttester`) |
| A handover that the new set has not accepted | Refused (`NotEnoughAttesters`) |
| A handover to a set where two of three addresses are held by nobody, accepted by the outgoing attesters in their place | Refused (`BadAttester`) |
| Attesters 1 and 2 hand over to attesters 2, 3 and 4, two of three, accepted by attesters 3 and 4 ([tx](https://sepolia.basescan.org/tx/0x116ccae4f376003fbb4011a050d9ee0cba7e316782d38a307e650456f0bb2eeb)) | 157,982 gas. `attesterSet` is still 1 |
| During the notice, attesters 3 and 4 approve the sale venue | Refused (`BadAttester`) |
| During the notice, attesters 1 and 2 approve the sale venue ([tx](https://sepolia.basescan.org/tx/0xdacae150f92b3a6a749b714a802bd1fcee055b577fa8bafd372ea4e276dd7be3)) | Accepted: the set in force still decides |
| 120 seconds after the handover | `attesterSet` is 2, with no transaction |
| A revocation of agent 1 that attesters 2 and 3 signed under the first set; both are in the new set | Refused (`BadAttester`): it names the first set |
| Agent 2 enrolled by attesters 1 and 2 | Refused (`BadAttester`) |
| Agent 2 enrolled by attesters 3 and 4 ([tx](https://sepolia.basescan.org/tx/0xf70fe870c8e1407ab6441128a11caf248ddf3fd75a0d0cc6ceb73b67b0500309)) | 214,721 gas |
| 120 seconds after its own approval | The venue approved by the first set is in force |
| Attesters 1 and 2 remove the sale venue | Refused (`BadAttester`) |
| Attesters 2 and 4 remove the sale venue ([tx](https://sepolia.basescan.org/tx/0x60dfb4e3ed87db5fbc1694c5f5deb55c8575927dff1276406c7fad0f5f6016bb)) | Accepted |
| Attesters 2 and 3 revoke agent 1, signing again under the new set ([tx](https://sepolia.basescan.org/tx/0x374f7cb20b1be18c683718b004f1ef3d9690b1dedf7d9b6a46b14217ba164fa7)) | Accepted. Account 1 is no longer an agent; account 2 still is |
| The handover signatures, sent again | Refused (`BadAttester`) |

The refusals were simulated on the chain's state at that moment; the other
steps are transactions, sent with `cast`: no script in this repository replays
the run. Two earlier runs the same day used the registry as it was before the
review ([`0xEcDD…8a4e`](https://sepolia.basescan.org/address/0xEcDD47fb89fC7514cd37aFFf3E2E97B881Cd8a4e)),
then before signatures named their set
([`0xAcD9…f814`](https://sepolia.basescan.org/address/0xAcD92D8Bc79342f79b5E4EF89e55c1077284f814)). Section 3.18 of the study.

## Attesters that are contracts, 17 November 2026

An attester can be a contract that signs by ERC-1271, for example a
multi-signature wallet, as well as a key. Until then a set of attesters was a
set of keys: an organisation that keeps its keys in a wallet with several
signers could not be one.

**What it gives.**

- **A member of a set is an address: a key or a contract.** Nothing says which
  when a set is appointed; the form of the signature does.
- **A key signs as before**, in 65 bytes. **A contract is named with what it
  accepts**: `abi.encode(member, signature)`. The registry asks that contract,
  by ERC-1271, whether it accepts the signature for the decision.
- **Only members are asked.** A contract that is not in the set is refused
  without being called, and a member counts once whatever it sends.
- **A key stays a key.** An account that a key controls can delegate to code
  (EIP-7702). The registry does not ask such an account as a contract: it
  signs by its key only, so the code it delegates to cannot take its seat.
- **Nothing else changes.** Threshold, set number, deadline and counters apply
  to a contract as to a key. A contract appointed by a handover accepts its
  appointment by answering yes to that handover.
- **A wallet can take back what it accepted** and that was not sent, for
  example by changing its owners; a key cannot. The exception is what the
  wallet approved on chain, as a Safe can: that approval outlives its owners.

**What it does not give.**

- **The registry believes what the contract answers.** A wallet whose owners
  can be changed, or a contract that can be upgraded, changes who decides
  without a handover and without the notice delay. The code of a contract
  attester has to be read before it is appointed, as a venue's is.
- **A contract accepts its appointment by answering yes once**, possibly to an
  empty signature that anyone can write. For a key, the acceptance shows that
  someone holds it; for a contract it shows nothing of the kind.
- **The threshold counts addresses, not people.** A wallet and one of its
  owners are two members and the same people.
- **A member that is a contract is given all the gas left, and its whole
  answer is copied.** It can make a decision expensive to send, or make it
  fail. Only the sender pays, and a contract that is not a member is never
  called.
- **What cannot be read is refused**: by a revert without data, or a panic,
  when the bytes do not decode; by `BadAttester` when they decode to an
  address that is not a member. Encodings other than the standard one that
  still decode are accepted.

**Cost.** A key's signature costs about 70 gas more to check than before. The
same venue approval costs <!--f:gas.17-->93,008<!--/f--> gas signed by two keys and <!--f:gas.18-->109,032<!--/f--> gas
signed by a key and a test wallet of two owners. On Base Sepolia, with a real
Safe of three owners, two of them signing, an enrollment cost 249,978 gas and
a venue approval 128,223.

**Tested.** <!--f:tests.ContractAttesters-->24<!--/f--> tests, with a small wallet written for them; one of
them uses a real EIP-7702 delegation. Two more run on a fork of Base Sepolia
against the Safe contracts deployed there (`test/fork/SafeBaseSepolia.t.sol`).
The symbolic proofs still use keys only: they do not cover a contract's
answer. The explicit error test on a recovered signature, found redundant by
the fifth pass, was removed with this change: one mutant is left explained
instead of two.

Run on Base Sepolia with a real Safe and a notice delay of 120 seconds:

| Step | Result |
| --- | --- |
| A Safe 1.4.1 created through Safe's own proxy factory: three owners, two must sign ([tx](https://sepolia.basescan.org/tx/0xcd0ddbde6fd05f9b948ed0280279175249fbfd1f909931b963cf5019138e111d)) | Safe [`0x75Bf…FBE1`](https://sepolia.basescan.org/address/0x75BfBf6A02AF5a05Df9dAC47AEd1EcBf9DddFBE1) |
| A registry is deployed with two attesters, the Safe and key 1, two of two | Registry [`0x4F8f…FCAE`](https://sepolia.basescan.org/address/0x4F8f69F116E2aA182999F6dd0D70e6677539FCAE) |
| Agent 1 is enrolled by key 1 and the Safe, owners 3 and 4 signing ([tx](https://sepolia.basescan.org/tx/0xda94d388dff207888cbbb46e5bcc536d9f3e96f066f2ba77dce810f61abbbcbc)) | 249,978 gas |
| Key 1 alone; the Safe alone | Refused (`NotEnoughAttesters`), both |
| Key 1 and the Safe with one owner's signature | Refused (`BadAttester`) |
| Key 1 and the Safe, whose owners signed the registry's digest instead of the Safe message | Refused (`BadAttester`) |
| Key 1 and the Safe, whose owners signed the removal of the venue | Refused (`BadAttester`) |
| Key 1 and an owner of the Safe signing as a key | Refused (`BadAttester`) |
| Key 1 and a contract that is not an attester and says yes to every question | Refused (`BadAttester`) |
| Key 1 named as a contract, and the Safe | Refused (`BadAttester`) |
| The Safe twice, signed by two different pairs of owners | Refused (`BadAttester`) |
| The sale venue is approved by key 1 and the Safe, owners 4 and 5 signing ([tx](https://sepolia.basescan.org/tx/0x03748bba05d455c11d661399f9fc247e48f6253c96b4e5ca115e0f39a5affff5)) | 128,223 gas |
| A handover to the Safe and key 2, accepted by key 2 only | Refused (`NotEnoughAttesters`) |
| The same handover, accepted by key 2 and one owner of the Safe | Refused (`BadAttester`) |
| The same handover, signed by key 1 and the Safe as the set in force, accepted by key 2 and the Safe as the new set ([tx](https://sepolia.basescan.org/tx/0xb5ef4ba02e937bfe209809528c3d75a2bfd202f696649e356f91af3f0a56dda8)) | 189,246 gas. `attesterSet` is still 1 |
| After the notice of 120 seconds | `attesterSet` is 2, key 1 is no longer an attester, the venue is in force |
| A revocation of agent 1 signed under the first set by key 2 and the Safe | Refused (`BadAttester`): it names the first set |
| The venue removed by key 1 and the Safe | Refused (`BadAttester`) |
| The account of key 2 delegates, by an EIP-7702 authorization, to a contract that says yes to every question ([tx](https://sepolia.basescan.org/tx/0x3e62f534d45d152b3711c119f7cae88a4083b8a70c4e40474d7c2d0d26f1beb9)) | The account holds `0xef0100` followed by that contract's address. Asked directly, it answers yes |
| The venue removed by key 2 named as a contract, and the Safe | Refused (`BadAttester`): an account that a key controls is not asked as a contract |
| The venue removed by key 2, signing as a key, and the Safe, owners 4 and 5 signing ([tx](https://sepolia.basescan.org/tx/0xc0e366afb0fd41759ae7701637a4ef16c5d82e4142e79f02e4ee1486e435a8ee)) | Accepted, 86,277 gas |
| Agent 1 revoked by key 2 and the Safe, owners 3 and 5 signing under the second set ([tx](https://sepolia.basescan.org/tx/0xd939b73e7362149bbb963dd5fa688dc4492776e59b50ee9596af6a35c4f92cdb)) | Accepted, 86,090 gas. Account 1 is no longer an agent |

The refusals were simulated on the chain's state at that moment; the other
steps are transactions, sent with `cast`: no script in this repository replays
the run. Owners and keys were made for the tests. An earlier run the same day
used the registry as it was before the review
([`0xa7F1…A1c2`](https://sepolia.basescan.org/address/0xa7F15B9e9864f4fD1859C0b06cE8Ae19D857A1c2)); the Safe was
created for it. Section 3.19 of the study.

## The base image checked, 17 November 2026

Every agent enrolled by attestation ran on the production image of dstack OS
0.5.12. It is exactly the image dstack published for that version, and it has
no way in.

- **The same image.** `tools/dstack_image.py` recomputes, from the published
  archive (`dstack-0.5.12.tar.gz`, SHA-256 `e3037d99…eb176`), the three boot
  registers that cover the firmware, the kernel, the initrd and the kernel
  command line: MRTD, RTMR1 and RTMR2. All three equal those of the eleven
  distinct quotes of our runs, on two machines (nine before the run below;
  version 0.4.1 wrongly said eleven). One byte changed in any of
  those files changes the register that covers it. The image hash our machines logged,
  `8db40cb2…15bd`, is that of the archive's file list.
- **The whole image.** The command line carries the root hash of the root
  file system, which the initrd mounts only through dm-verity with that hash;
  `veritysetup verify` confirms it for the published file system.
- **No way in.** No SSH, Dropbear or Telnet server, no qemu guest agent, no
  login on the console, root's password locked. The SSH keys that the
  provider's pre-launch script installs therefore open nothing.
- **Every night**, a job downloads the archive, checks its hash and compares
  the registers of every archived quote.

Not done: the image was not rebuilt from its sources (dstack builds it with
Yocto inside Docker; this workspace has neither the Docker service nor access
to the sites the build downloads from), and RTMR0, which covers the virtual
hardware that QEMU describes, was not recomputed. It is equal in all eleven
quotes. Section 3.20 of the study.

## Our own pre-launch script, 17 November 2026

The provider's 406-line pre-launch script no longer runs before our agent.
`examples/enclave-agent/manifest/prelaunch-ours.sh` replaces it: one `echo`,
nothing else. No registry login, no password, no SSH key, nothing read from
the host.

- **Predicted, then measured.** The compose hash was computed here before
  deployment (`compose-hash.py ../v3/docker-compose.yml prelaunch-ours.sh`,
  `024261d8…39b5`); Phala Cloud's prepared manifest and the machine gave the
  same value. The code identity was predicted too, from an earlier quote.
- **Same image.** MRTD, RTMR1 and RTMR2 equal the published 0.5.12 image.
- **Enrolled.** Quote verified on Base Sepolia
  ([tx](https://sepolia.basescan.org/tx/0x22347b142a4333ac121c4b274911946b7f35f7c0d689a9a704bec610d06f56ea),
  3,719,468 gas), agent enrolled without an attester signature
  ([tx](https://sepolia.basescan.org/tx/0x8cddffe6108189ac7a8201b0c6cc796edf59e063bbf62a00f57b86bb7819dc9e),
  201,819 gas), through verifier
  [`0x120D…3A74`](https://sepolia.basescan.org/address/0x120D6d17c744900e94Ef59Fa6123Ac29e82D3A74) and registry
  [`0xE784…aD52`](https://sepolia.basescan.org/address/0xE78420EDf016b1249F2F8664ab172240C43BaD52).
  A quote made under the provider's script is refused (`UnknownCode`).
- **Restarted.** Same manifest, our script again, a new key rotated in on the
  same account
  ([tx](https://sepolia.basescan.org/tx/0xb688489e82c51e24a0b2073a2b0557c2df7af0bd58741bbc5b60b6162a1fac5f)).

Everything that runs before the program is now either dstack's, in the
approved base image, or ours. Section 3.21 of the study.

## An enclave agent pays by x402, 16 November 2026

A second program, in another machine, paid for a public x402 page from its
agent account.

- **Prepared before the machine existed.** The program's compose hash, its
  code identity, a `DstackConfigIdVerifier` approving that identity only, a
  registry, and the address of the agent's future account, which received 20
  test USDC from Circle's faucet.
- **Enrolled with the quote alone.** The machine's quote carried the identity
  computed beforehand, although it was not the machine of the first run
  ([attest](https://sepolia.basescan.org/tx/0xac4c5fe0debd7322a151ce1fc962bf445c8f9bd4a555efcf8bbfa8da0f12f268), 3,719,444 gas; [enroll](https://sepolia.basescan.org/tx/0x0e38885b28658477fa07fb4d9240739a1ce72c742ebf88dcf6ba0b71ed87a2cd)).
- **The agent pays.** It asked for `https://x402.org/protected`, received HTTP
  402, signed a 0.01 USDC payment as a message of its account, and received
  the page. The hosted x402.org facilitator checked the signature through
  ERC-1271 and settled it
  ([tx](https://sepolia.basescan.org/tx/0x89e0a73920d855494cbad29a8ec0035a4e07c84da12e409b6c1e2f74aade5ea0), 98,705 gas paid by the facilitator). Four payments in all. The
  agent's account and keys never held ETH.
- **The program decides where the money goes.** The shop, the network, the
  token and a cap of 0.02 USDC per purchase are fixed in the measured code.
  Asked to pay from another agent's account or from a plain wallet, its
  signature was refused.
- **Emergency stop.** [Frozen](https://sepolia.basescan.org/tx/0x8e55e045a422f3073e56e17964cfdff3af783f5dcd2ea1ad2dd6284c9f02fb3e) by its sponsor, the agent's payment was
  refused by the facilitator and nothing reached the chain; unfrozen, it paid
  again.
- **The money follows the agent, not the key.** After a restart the machine
  had a new key, which could not pay. A new quote [rotated](https://sepolia.basescan.org/tx/0x49c322020ed96cc59537c0d7c138bed963d4827fd6e897ad90762257080e9fb7) it, and the
  new key [paid](https://sepolia.basescan.org/tx/0xc9d1118cfdd7647e082a1a207cb35f0c16617e9d108d7a3073d88efb84cdf3b8) from the same account. The agent then
  [minted](https://sepolia.basescan.org/tx/0xe1f1beb4b3574d35014dbae49c304913eb8c8df10aaa97276b51df6aed28d51f) a token holding the hash of that payment.

Every step, the addresses and the limits: `examples/enclave-agent` and section
3.14 of the study.

Three defects of that program were then fixed in a third one: it tries again
when the shop fails, its answer says whether the payment was settled, and it
has a budget of 0.05 USDC for the life of its key. Its compose hash was
computed from this repository before deployment, with the provider's public
pre-launch script, and the machine measured the same value. Enrolled on Base
Sepolia, it paid four times ([first payment](https://sepolia.basescan.org/tx/0xeb9af69f1d33e8939ae407097ea5c54b93b9d151fbbe0993920faa368c63dbfa)) and then refused to sign:
its budget was spent (section 3.15 of the study).

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

On 16 November 2026 the same payment was made on Base Sepolia, by an agent
running in a confidential VM, through the hosted x402.org facilitator (see "An
enclave agent pays by x402" above). The test USDC there runs the same code
(same script, block 59,533,350).

## Use cases

Tested here: x402 USDC payments (reference facilitator on a local chain, hosted test facilitator on Base Sepolia), reputation badges, sale, collateralised loans and staking between agents, wrapping of any
existing ERC-721, and Uniswap V3 liquidity positions held and traded by agents
only. Supported by design but without a dedicated test: art and collectibles
for agents, documents and credentials, links to ERC-8004 agent identities.
See the study for the full table.

## Language

The root of the repository is in English. The two archived tracks under
`archive/` keep their original French comments.

## License

CC0-1.0, except `examples/enclave-agent/manifest/prelaunch.sh`: a third-party
file kept unchanged, under the Apache License 2.0 (`LICENSE-prelaunch` beside it).
