# Agent-Only Tokens

A research prototype for an ERC-721 extension whose tokens can only be held and
moved by AI agent accounts. No human-held wallet can mint, receive, transfer,
list, pledge or burn them, including on secondary markets.

**Status: unaudited draft. Never deployed. Tests run on a local simulated EVM only.**
Do not use with real assets.

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

`src/ERC721AgentOnly.sol` (54 lines) overrides three OpenZeppelin hooks:

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
| `src/ERC721AgentOnly.sol` | The standard: the three rules | 54 |
| `src/AgentAccount.sol` | An agent's account, with no human owner, driven by a rotating session key. Single calls, batches, relayed calls, ERC-1271 | 112 |
| `src/AttestedAgentRegistry.sol` | Reference registry: k-of-n attesters, refundable bond, expiring keys, optional ERC-8004 identity link | 213 |
| `src/AgentSwap.sol` | Fixed-price sale between agents | 50 |
| `src/AgentLoan.sol` | Collateralised loan between agents | 84 |
| `src/AgentWrapped721.sol` | Wrapper that makes any existing ERC-721 agent-only | 80 |
| `src/AgentWrappedUniV3.sol` | Non-unwrappable wrapper for Uniswap V3 liquidity positions | 95 |
| `src/AgentReputationBadge.sol` | Reputation badges: agent-only and soulbound (ERC-5192). An issuer offers, the agent claims; issuers post a refundable deposit and have a daily quota | 203 |
| `archive/` | Two earlier tracks that were set aside (signed-intent core in Solidity, Rust model) | |

## Running the tests

Requires [Foundry](https://book.getfoundry.sh/) and Node.js.

    npm install
    git clone --depth 1 --branch v1.9.7 https://github.com/foundry-rs/forge-std lib/forge-std
    forge test

Thirty-six tests. They cover: classic ERC-721 behaviour between agents,
refusal of humans as holder, recipient, minter or approved operator, refusal
of unsolicited tokens and of unapproved wrapper contracts, sale, loan (repaid
and defaulted), session-key rotation, single, batched and relayed calls,
ERC-1271 signatures, attester threshold, freeze and revocation, and the
ERC-8004 identity check, and reputation badges (claim by the named agent only,
no transfer or approval, revocation, issuer deposit, quota and exit).

One test is fuzzed over 512 random addresses. One is a stateful invariant
test: two agents, a human and an unapproved contract perform 128 runs of 100
random actions (mint, approve, transfer, list, buy, lend, repay, claim,
freeze), and after every action no token may be held by, or approved for,
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

## Gas

Execution gas per transaction, measured locally with `forge test --isolate`,
so that each call pays for its first access to storage. On an L2 such as Base
the L1 data fee comes on top and is not measured here.

| Operation | Gas |
| --- | --- |
| Plain ERC-721 `transferFrom`, for reference | 55,582 |
| Agent-only `transferFrom`, called directly | 75,332 |
| Agent-only `transferFrom`, through the agent account | 81,574 |
| Agent-only mint, through the agent account | 132,773 |
| List for sale | 108,150 |
| Buy (NFT against an ERC-20) | 110,365 |
| First enrollment (deploys the account, 2 attester signatures) | 1,154,831 |
| Key rotation (2 attester signatures) | 52,933 |
| Badge offer, by an issuer | 254,919 |
| Badge claim, through the agent account | 113,998 |

The standard adds about 20,000 gas to a transfer: the registry is asked about
the caller, the holder and the recipient.

## Known limits

- "No human" rests on the attesters, who also approve venues. A dishonest
  approved venue could wrap tokens for humans. Attesters are fixed at deployment.
- No real attestation (TEE or otherwise) is wired in. The registry only checks
  attester signatures.
- A wrapper deployed as unwrappable is an exit door back to a classic NFT.
  A non-unwrappable wrapper needs one small adapter per protocol; only the
  Uniswap V3 one exists.
- The standard protects the NFT, not what it yields: tokens withdrawn from a
  position are ordinary ERC-20s.
- A buyer must check a wrapped position in the same batch as its purchase
  (`requireLiquidity`), otherwise a seller can empty it right before the sale.
  Fees already earned can always be collected by the seller before selling.
- If attesters remove a venue while it holds tokens, those tokens are stuck
  until the venue is approved again.
- A human can lend through the loan venue, but can never receive the token:
  on default it stays in the venue until the borrower repays.
- A classic NFT sent to a wrapper with a plain `transferFrom`, instead of
  `depositFor`, is stuck there.
- Tokens of a retired or revoked agent stay where they are.
- Staking is not implemented. Mint fees and quotas are left to each collection.
- An agent account cannot sign an x402 `exact` payment as specified today,
  which expects a plain key signature.
- No audit and no external review yet. The review above is the author's own.

## Use cases

Tested here: reputation badges, sale and collateralised loans between agents, wrapping of any
existing ERC-721, and Uniswap V3 liquidity positions held and traded by agents
only. Supported by design but without a dedicated test: art and collectibles
for agents, documents and credentials, links to ERC-8004 agent identities.
See the study for the full table.

## Language

The root of the repository is in English. The two archived tracks under
`archive/` keep their original French comments.

## License

CC0-1.0.
