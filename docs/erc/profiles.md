# The same rules for other token standards

The proposal (`erc-agent-only-tokens.md`) is written for ERC-721. Its rules are
not specific to one token standard: they say who may take part in a movement
or an approval, whatever is moved. This note states them once for any token,
then the ERC-1155 profile, which is implemented and tested, and what an ERC-20
profile would change, which is not.

## The rules, for any token

With *recognised*, *caller*, *holder*, *grant* and *granter* as defined in the
proposal:

1. Any mint, transfer or burn reverts if the caller is not recognised.
2. The recipient of a mint or a transfer must be recognised, and, unless the
   caller is a venue, must be the caller itself: the recipient pulls.
3. A transfer or a burn reverts if the holder of what is moved is not
   recognised.
4. A grant of an approval reverts if the account approved, the caller, the
   granter or the holder is not recognised. Clearing an approval is always
   possible.
5. Every transfer, burn and grant needs the authority the base standard
   defines (the holder, or an account it approved).
6. The registry is fixed for the life of the token, and no function bypasses
   these rules.

## ERC-1155 profile

`src/ERC1155AgentOnly.sol` (<!--f:lines.ERC1155AgentOnly-->62<!--/f--> lines),
on OpenZeppelin Contracts 5.

- **Every id of a batch is under the same rules.** The checks are on the
  caller, the holder and the recipient, which a batch shares; one check covers
  the whole batch.
- **There is no approval of a single token** in ERC-1155. `setApprovalForAll`
  is the only grant; the owner is both the caller and the holder.
- **Same interface, same identifier.** `IERC1155AgentOnly` has the single
  function `agentRegistry()`, so its ERC-165 identifier is `0x0d1cfcae`, as for
  ERC-721. Which profile a token follows is told by the token interface it
  also advertises (`0xd9b67a26` for ERC-1155).
- **Receiving needs an answer.** ERC-1155 delivers to a contract only if it
  answers `onERC1155Received` (or the batch version). Agent accounts did not:
  they could never have received an ERC-1155. `AgentAccount` now answers both;
  accounts made by registries deployed before 18 November 2026 still cannot
  receive ERC-1155 tokens, since an account's code is fixed when its registry
  is deployed.

**Tested.** A conformance suite for this profile
(`test/conformance/ERC1155AgentOnlyConformance.sol`,
<!--f:tests.Reference1155-->16<!--/f--> tests, single and batch movements) that
our implementation passes, and that eight implementations each missing one
check all fail (`tools/conformance.py`). With real agent accounts and our
registry (`test/AgentOnly1155.t.sol`): an account mints to itself, another
pulls with an approval, a push and an approval to a human are refused, and a
frozen agent's units do not move. The 9 mutants of the contract are caught.

## ERC-20: what would change (not implemented)

The rules apply as written, but they fit fungible tokens less well:

- **`transfer` becomes useless outside a venue.** It is a push: the caller is
  the sender, not the recipient, so it always reverts unless the caller is a
  venue. Payments would go through `approve` then `transferFrom` by the payee,
  or through a venue.
- **x402 and EIP-3009 payments are pushes too.** `transferWithAuthorization` is
  submitted by a facilitator for the payee: the facilitator would have to be a
  venue, and the recipient check would then fall on the payee.
- **Allowances are amounts.** An allowance left to an account that then stops
  being recognised cannot be used (rule 1), as for ERC-721.

An agent-only stablecoin is therefore possible but would need its payment flows
redesigned around venues; an agent-only ERC-20 for credits or shares between
agents is the simpler case. Neither was written.
