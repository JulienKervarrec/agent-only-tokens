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

`src/ERC721AgentOnly.sol` (46 lines) overrides three OpenZeppelin hooks:

1. Only an agent or an approved venue can hold a token or be approved for it.
2. Only an agent or an approved venue can trigger a mint, transfer or burn.
3. An agent only receives a token if it pulls it itself. Nobody can push an
   unsolicited token to an agent.

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
| `src/ERC721AgentOnly.sol` | The standard: the three rules | 46 |
| `src/AgentAccount.sol` | An agent's account, with no human owner, driven by a rotating session key | 77 |
| `src/AttestedAgentRegistry.sol` | Reference registry: k-of-n attesters, refundable bond, expiring keys, optional ERC-8004 identity link | 201 |
| `src/AgentSwap.sol` | Fixed-price sale between agents | 48 |
| `src/AgentLoan.sol` | Collateralised loan between agents | 75 |
| `src/AgentWrapped721.sol` | Wrapper that makes any existing ERC-721 agent-only | 68 |
| `src/AgentWrappedUniV3.sol` | Non-unwrappable wrapper for Uniswap V3 liquidity positions | 67 |
| `archive/` | Two earlier tracks that were set aside (signed-intent core in Solidity, Rust model) | |

## Running the tests

Requires [Foundry](https://book.getfoundry.sh/) and Node.js.

    npm install
    git clone --depth 1 --branch v1.9.7 https://github.com/foundry-rs/forge-std lib/forge-std
    forge test

Fourteen tests, one of them fuzzed. They cover: classic ERC-721 behaviour
between agents, refusal of humans as holder, recipient, minter or approved
operator, refusal of unsolicited tokens and of unapproved wrapper contracts,
sale, loan (repaid and defaulted), session-key rotation, relayed calls and
ERC-1271 signatures, attester threshold, freeze and revocation, and the
ERC-8004 identity check.

`test_RealUniswapV3Position` runs against the official Uniswap V3 bytecode
(npm packages `@uniswap/v3-core` 1.0.1 and `@uniswap/v3-periphery` 1.4.4)
deployed in the simulated chain: pool creation, position, wrapping, a
third-party swap, sale to another agent, fee collection by the buyer and
liquidity withdrawal.

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
- A seller can empty a wrapped position right before a sale. The buyer-side
  check is not implemented.
- Tokens of a retired or revoked agent stay where they are.
- Staking is not implemented. Mint fees and quotas are left to each collection.
- An agent account cannot sign an x402 `exact` payment as specified today,
  which expects a plain key signature.
- Gas costs are not measured. No audit.

## Use cases

Tested here: sale and collateralised loans between agents, wrapping of any
existing ERC-721, and Uniswap V3 liquidity positions held and traded by agents
only. Supported by design but without a dedicated test: art and collectibles
for agents, documents and credentials, links to ERC-8004 agent identities.
See the study for the full table.

## Language

The root of the repository is in English. The two archived tracks under
`archive/` keep their original French comments.

## License

CC0-1.0.
