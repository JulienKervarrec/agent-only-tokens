# Brief for an external audit (draft)

Prepared on 23 November 2026 (step 6.4 of the plan). **Nothing has been sent to
anyone and no quote has been asked for**: whether, when and in which form to
have the contracts audited is still to be decided. This page is what an
auditor would receive.

## What this is

An ERC-721 extension whose tokens can only be held and moved by accounts with
no human owner, driven by a key that a registry recognises as an agent's
(`README.md`; a short article in [`paper.md`](paper.md); the full study in
[`study.md`](study.md)). A research prototype: deployed on the Base Sepolia
test network only, never audited by a person.

## Scope

The scope is frozen on a tagged release when the audit is ordered; the figures
below are those of the repository today.

**First: the standard and what every token relies on.**

| Contract | Lines | What to look for |
| --- | --- | --- |
| `src/ERC721AgentOnly.sol` | <!--f:lines.ERC721AgentOnly-->72<!--/f--> | The three rules: any way for an account the registry does not recognise to hold, receive, move or be approved for a token |
| `src/IAgentRegistry.sol`, `src/IERC721AgentOnly.sol` | <!--f:lines.IAgentRegistry-->10<!--/f-->, <!--f:lines.IERC721AgentOnly-->10<!--/f--> | The interface a token and a registry share |
| `src/AgentAccount.sol` | <!--f:lines.AgentAccount-->153<!--/f--> | An account with no owner: orders signed by the current key, replay across accounts, chains and clones, ERC-1271, initialisation of clones |
| `src/AttestedAgentRegistry.sol` | <!--f:lines.AttestedAgentRegistry-->525<!--/f--> | Enrollment, expiry, freeze, revocation, exit and bond; the notice delay on what widens; the halt; the handover between sets of attesters; contract attesters; replay of every signed decision |
| `src/AgentSwap.sol` | <!--f:lines.AgentSwap-->64<!--/f--> | The sale venue: settlement in one transaction, stale listings, reentrancy |
| `src/AgentAllowance.sol` | <!--f:lines.AgentAllowance-->126<!--/f--> | The spending limit: nobody can raise it, a new key does not reset it, period boundaries |

**Second: venues and wrappers built on it.**

| Contract | Lines |
| --- | --- |
| `src/AgentLoan.sol` | <!--f:lines.AgentLoan-->120<!--/f--> |
| `src/AgentStaking.sol` | <!--f:lines.AgentStaking-->130<!--/f--> |
| `src/AgentWrapped721.sol` | <!--f:lines.AgentWrapped721-->80<!--/f--> |
| `src/AgentWrappedUniV3.sol` | <!--f:lines.AgentWrappedUniV3-->98<!--/f--> |
| `src/AgentReputationBadge.sol` | <!--f:lines.AgentReputationBadge-->218<!--/f--> |
| `src/ERC1155AgentOnly.sol`, `src/IERC1155AgentOnly.sol` | <!--f:lines.ERC1155AgentOnly-->62<!--/f-->, <!--f:lines.IERC1155AgentOnly-->11<!--/f--> |

**Third, if the budget allows: enrollment verifiers** (`src/experimental/`).
They decide who is an agent when a registry uses hardware attestation, and
they parse the output of a third party's verifier.

| Contract | Lines |
| --- | --- |
| `TdxQuoteVerifier.sol` | <!--f:lines.TdxQuoteVerifier-->122<!--/f--> |
| `DstackConfigIdVerifier.sol` | <!--f:lines.DstackConfigIdVerifier-->70<!--/f--> |
| `DstackConfigIdZkVerifier.sol` | <!--f:lines.DstackConfigIdZkVerifier-->79<!--/f--> |
| `DstackEnrollmentVerifier.sol`, `Sha384.sol` | <!--f:lines.DstackEnrollmentVerifier-->138<!--/f-->, <!--f:lines.Sha384-->92<!--/f--> |
| `TdxEnrollmentVerifier.sol`, `DualKey.sol` | <!--f:lines.TdxEnrollmentVerifier-->41<!--/f-->, <!--f:lines.DualKey-->72<!--/f--> |

**Out of scope.** The agent programs (`examples/enclave-agent/`, JavaScript
that runs in a confidential machine) unless an off-chain review is added;
Automata's DCAP verifier, Intel's data, RISC Zero, dstack and Phala Cloud;
Circle's USDC; x402 facilitators; OpenZeppelin Contracts 5.4.0, on which the
contracts are built.

## What must hold

1. No account that the registry does not recognise as an agent or an approved
   venue ever holds a token, receives one, moves one, or is approved for one,
   including during a callback.
2. An agent never loses a token or funds through a signature it did not give
   for that purpose: an order, a message or a decision signed for one account,
   one registry, one chain or one nonce cannot be used for another.
3. A decision that widens what a registry accepts, or changes who decides,
   takes effect only after the notice delay; a removal and a halt are
   immediate; under a halt nothing is enrolled.
4. A venue never owes more than it holds, and gives back what it was given.
5. Nobody can raise an allowance's limit, and a new key does not reset it.

## Threat model

Section 2 of [`paper.md`](paper.md): who the adversary is, what it can do, and
what the design answers or does not. What no contract can prevent (a person
who owns the machine or the sponsor role, wrapping by a recognised agent,
forged hardware quotes after a physical attack) is in its section 8 and in
section 7 of the study; a report that restates one of these is useful only if
it shows a consequence not written there.

## What already exists

| Check | Where |
| --- | --- |
| <!--f:tests-->369<!--/f--> unit, fuzz and invariant tests | `test/`, `forge test` |
| <!--f:proofs-->13<!--/f--> symbolic proofs, the registry's also run against <!--f:proofs.broken-->12<!--/f--> registries broken on purpose | `test/halmos/`, `tools/proofs.py` |
| Mutation testing: <!--f:mutants-->347<!--/f--> mutants, all caught but <!--f:mutants.accepted-->1<!--/f--> accepted | `tools/mutate.py`, weekly |
| Static analysis against a list of accepted findings | `tools/slither_check.py`, `tools/slither-accepted.json` |
| Conformance suites that a second implementation (on Solady) passes | `test/conformance/`, `tools/conformance.py` |
| Eight review passes and the review of a second implementation, five of them by independent AI reviewers, and what each found | Study, sections 2.3 to 2.10 and 3.33 |
| Tests against the real chain, every night | `test/fork/`, `nightly.yml` |

One command replays all of it: `bash tools/reproduce.sh`. Compiler: solc
0.8.28, optimizer on (200 runs), EVM version `cancun` (`foundry.toml`).

## Questions we would most like answered

- **The registry's clock.** Announcements, halts, handovers and deadlines
  interact in `AttestedAgentRegistry`: is there an order of decisions that
  lets something take effect earlier than its notice, or survive a halt?
- **Signatures.** Can any signed decision, order or message be replayed
  (another registry, account, chain, set of attesters, nonce), or be confused
  with one of another kind? ERC-1271 messages of an account are accepted by
  third parties (USDC, sign-in): can one be used as another?
- **Callbacks.** `safeTransferFrom` and ERC-1155 hooks call the recipient:
  any way to hold or approve a token inside a callback and keep it?
- **Clones.** Every account is an ERC-1167 clone that reads its registry and
  agent id from its own code: can a clone be made to answer for another agent?
- **Money.** Bonds, loans with a currency that takes a fee, staking rewards,
  allowance periods: rounding, griefing, funds left behind.
- **Verifiers.** The parsing of the DCAP verifier's output, the fields that
  identify the code, and what a registry inherits when a third party it relies
  on is wrong or stops (it happened: study, section 3.28).

## Two possible forms

| | A public contest | One auditor or firm |
| --- | --- | --- |
| Finds | Many eyes for a short time; good at breadth | Fewer people for longer; good at depth and at the design |
| Needs from us | A fixed scope, a clear list of known limits (duplicates of them are paid otherwise), time to judge reports | A fixed scope, availability for questions |
| Result | A list of findings by severity | A report, usually with a second look at the fixes |

Either way: the scope is frozen on a tag, every finding is fixed or accepted
in writing, and the report is published with the code.
