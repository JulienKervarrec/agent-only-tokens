---
eip: TBD
title: Agent-Only Tokens
description: ERC-721 tokens that only accounts recognised by an agent registry can hold, move or approve
author: TBD (@TBD)
discussions-to: TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-11-18
requires: 165, 721
---

## Abstract

This proposal extends [ERC-721](./eip-721.md) so that a token can only be
received, moved or approved by accounts that an external registry recognises
as agents, or as venues the registry has approved. A compliant token asks the
registry two questions, `isAgent(address)` and `isVenue(address)`, on every
movement and every grant of an approval. Outside a venue, a recipient must
pull the token itself, so no account receives a token it did not ask for
unless a venue delivers it. A token whose holder stops being
recognised does not move until the holder is recognised again. How the
registry decides who is an agent is out of scope: it can change without
touching the token.

## Motivation

Software agents now hold wallets, buy services and trade assets on chain.
Some assets only make sense between agents: credentials, licences, seats or
positions meant for programs, whose value would be lost if a human could buy
them on an ordinary marketplace. No standard lets an asset say "only agents".

Two shortcuts do not work. Checking that an address holds code has never shown
that a program controls it: humans control smart-contract wallets, and since
[EIP-7702](./eip-7702.md) even an externally owned account can carry code.
Checking that an address is listed in an agent identity registry proves only
that someone registered it: an identity in [ERC-8004](./eip-8004.md) is itself
an ERC-721 that a human can own and sell.

This proposal separates the two concerns, as [ERC-3643](./eip-3643.md) does
with its identity registry for regulated securities, but without ERC-3643's
privileged role, forced transfers or recovery: the token enforces the rules on
every movement, and a registry, chosen at deployment, says who is eligible. A registry can rest on
attesters, on hardware attestation of the agent's runtime, or on any future
proof, without a change to the tokens that rely on it.

Two threats shaped the rules. An unsolicited token sent to an agent's wallet
can raise that agent's permissions, or carry instructions in its metadata,
ahead of a prompt injection: here, outside a venue, no agent receives a token
it did not pull. And approvals are the usual path of drainers: here, approvals
can only go to recognised accounts.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interfaces

```solidity
interface IAgentRegistry {
    /// True if `account` is the account of an active agent.
    function isAgent(address account) external view returns (bool);
    /// True if `account` is an approved venue contract.
    function isVenue(address account) external view returns (bool);
}

/// A compliant token is a full ERC-721 that exposes its registry.
/// Its ERC-165 identifier is `type(IERC721AgentOnly).interfaceId`.
interface IERC721AgentOnly /* is IERC165, IERC721 */ {
    function agentRegistry() external view returns (IAgentRegistry);
}
```

The ERC-165 identifier of `IERC721AgentOnly` is `0x0d1cfcae`, the selector of
`agentRegistry()`: the inheritance written as a comment is not part of it.

### Definitions

- An account is *recognised* when the registry answers `true` to `isAgent` or
  to `isVenue` for it. A *venue* is an account for which `isVenue` answers
  `true`.
- The *caller* of a function of the token is `msg.sender` of the call to the
  token. An implementation that supports [ERC-2771](./eip-2771.md) MAY treat
  the forwarded sender as the caller, only for a forwarder fixed at
  deployment, and MUST document it; the forwarded sender then replaces
  `msg.sender` in every rule.
- The *holder* of a token is the account `ownerOf` returns for it.
- A function *grants an approval* when it sets an approved address for a token
  to a non-zero address, sets an operator for all of an owner's tokens, or
  gives any other account a right to move a token. The *granter* is the
  account whose authority grants it: the caller, or the signer of a signed
  approval.

### Rules

1. The token MUST implement ERC-721 in full. It MUST return `true` from
   `supportsInterface` for the identifiers of `IERC721AgentOnly`, ERC-721 and
   [ERC-165](./eip-165.md).
2. Any mint, transfer or burn MUST revert if the caller is not recognised.
3. The recipient of a mint or a transfer MUST be recognised.
4. If the caller is not a venue, the recipient of a mint or a transfer MUST be
   the caller itself.
5. Any function that grants an approval, `approve` and `setApprovalForAll`
   included, MUST revert if the account it approves, the caller, the granter,
   or the holder of the token (for an operator, the owner of the tokens) is
   not recognised. Clearing an approval (`approve`
   to the zero address, `setApprovalForAll` with `false`) MUST be possible
   whatever the registry answers.
6. `agentRegistry()` MUST return the same address for the life of the token.
   No function of the token MAY mint, move or burn a token, or grant an
   approval, without meeting rules 2 to 5, 7 and 8.
7. A transfer or a burn MUST revert if the current holder is not recognised.
   A token whose holder stops being recognised therefore stays with it, and
   moves again once the holder is recognised again.
8. A transfer or a burn, through any function, MUST revert unless the caller
   is the holder, the approved address for the token, or an operator of the
   holder, as ERC-721 defines them. A grant of an approval MUST revert unless
   the granter is the holder (for an operator, the owner of the tokens) or,
   for the approved address of a single token, an operator of the holder. A
   mint MUST NOT change the holder of an existing token. The public functions
   of ERC-721 already meet this rule; it matters for any other function.

The token MUST NOT treat as recognised an account that the registry does not
recognise, and MUST NOT use the presence of code at an address, nor the
ownership of an identity token, as a test of eligibility. It MAY add further
restrictions. This proposal defines no errors and no events: a refused call
MAY revert with any data.

### Registries and venues

A registry SHOULD answer both questions in constant gas and SHOULD NOT revert:
a registry that reverts blocks every movement of every token that relies on
it. A registry SHOULD make a decision that widens eligibility (a new venue, a
new way of proving agents, new deciders) take effect only after a public
delay, and a decision that narrows it (a freeze, a revocation) take effect at
once. A registry SHOULD NOT recognise as an agent an account that a human can
control through another asset, such as an [ERC-6551](./eip-6551.md)
token-bound account whose token a human may hold.

A venue SHOULD be a contract whose code cannot change, approved by the hash of
its code. A venue SHOULD deliver a token only to an account that asked for it,
in the same call or earlier, such as the buyer of a sale or the lender of a
defaulted loan.

## Rationale

**Why a separate registry.** Proving that an account is an agent is an open
problem with several partial answers (attesters, hardware attestation,
zero-knowledge proofs of an attestation, proofs of inference). Fixing one of
them in the token would freeze the asset to today's answer. Two view functions
are the smallest surface that lets the proof change while the token stays.

**Why the recipient pulls (rule 4).** An unsolicited token is not neutral for
an agent: it can carry instructions in its metadata, or raise permissions that
depend on holdings. Requiring the recipient to be the caller gives every agent
a veto over what it receives from anyone but a venue. Venues are the exception because a sale, a loan
or an escrow must deliver to a party other than the caller; a venue is
approved by the registry precisely so that its code can be reviewed first.

**Why the granter and the holder must be recognised (rule 5).** Without it, a
frozen holder, or an operator it approved earlier, could grant an approval
during the freeze, so that the token moves the moment the holder is unfrozen,
before anyone reacts. Clearing an approval only reduces what can happen, so it
stays free and does not depend on the registry. Rule 5 covers every function
that grants an approval, so that a signed permit or a delegation role cannot
open a way around it.

**Why every path needs ERC-721 authorisation (rule 8).** Rules 2 to 7 say who
may take part in a movement, not whose token it is. Without rule 8, a function
that lets a recognised venue or administrator move or burn any token would
meet them all.

**Why a frozen holder's tokens stay (rule 7).** A registry that freezes or
revokes an agent must be able to stop its tokens at once, including through a
listing or an approval left behind. Seizing them instead would need a
privileged transfer, which rules 6 and 8 forbid: the token has no owner who
could move someone else's token.

**Why rule 2 with rules 3 to 5.** Most of rule 2 follows from the others: an
unrecognised caller can neither receive a token nor be granted an approval. It
still matters on its own for burns, which have no recipient: an operator
approved while recognised that later stops being so cannot burn.

**Relation to [ERC-8004](./eip-8004.md).** An ERC-8004 identity says who an
agent is; this proposal says what only agents may hold. A registry may use
ERC-8004 identities, for instance to require that the sponsor of an agent owns
its identity, but the identity alone is not a proof: it can be sold to anyone.

**Relation to ERC-6551.** A token-bound account is controlled by whoever holds
the token it is bound to, hence the requirement on registries above.

**Relation to EIP-7702.** The presence of code at an address does not
distinguish a human from a program, and since EIP-7702 its absence does not
either. The token never looks at code.

## Backwards Compatibility

A compliant token is a full ERC-721. Wallets, explorers and indexers read it
as any other. Movements that rules 2 to 8 forbid revert, as ERC-721 allows an
implementation to throw in situations beyond those it lists. In practice,
outside a venue, a holder cannot push a token: the recipient pulls it. An
ordinary marketplace that takes an approval and pushes the token to a buyer
fails, unless the registry approves it as a venue; so does a primary sale or
an airdrop contract that mints to its buyers. A holder cannot push a token
into a venue either: it approves the venue, which pulls. `safeTransferFrom`
works for a recipient that pulls; the usual `onERC721Received` check still
applies. `getApproved` and `isApprovedForAll` keep reporting an approval whose
account has stopped being recognised, although it can no longer be used.

## Test Cases

A conformance suite in Foundry is in
[`assets/erc-TBD/ERC721AgentOnlyConformance.sol`](../assets/erc-TBD/ERC721AgentOnlyConformance.sol).
It brings its own registry, where anyone can set who is an agent or a venue,
and asks the implementation under test for two hooks: deploy the token on a
given registry, and let an account mint one token to itself; a burn is
optional. Its seventeen tests cover rules 1 to 5 and 7; rules 6 and 8 cannot
be checked from outside the token. The reference implementation passes it, as
does a second implementation on another ERC-721 library, written from this
text alone; nine implementations that each omit one check fail it.

## Reference Implementation

On OpenZeppelin Contracts 5.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

interface IAgentRegistry {
    function isAgent(address account) external view returns (bool);
    function isVenue(address account) external view returns (bool);
}

interface IERC721AgentOnly {
    function agentRegistry() external view returns (IAgentRegistry);
}

abstract contract ERC721AgentOnly is ERC721, IERC721AgentOnly {
    IAgentRegistry public immutable override agentRegistry;

    error NotAgent(address account);
    error NotPulledByRecipient();

    constructor(IAgentRegistry registry_) {
        agentRegistry = registry_;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC721AgentOnly).interfaceId || super.supportsInterface(interfaceId);
    }

    function _allowed(address account) private view returns (bool) {
        return agentRegistry.isAgent(account) || agentRegistry.isVenue(account);
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address caller = _msgSender();
        // Rule 4 is met when the caller is the recipient (pull, or mint to self): one question
        // to the registry then covers both the caller and the recipient.
        bool pull = to == caller;
        bool venue;
        if (pull) {
            if (!_allowed(caller)) revert NotAgent(caller);
        } else {
            venue = agentRegistry.isVenue(caller);
            if (!venue && !agentRegistry.isAgent(caller)) revert NotAgent(caller);
        }
        address from = _ownerOf(tokenId);
        if (from != address(0) && from != caller && !_allowed(from)) revert NotAgent(from);
        if (!pull && to != address(0)) {
            if (!_allowed(to)) revert NotAgent(to);
            if (!venue) revert NotPulledByRecipient();
        }
        return super._update(to, tokenId, auth);
    }

    function _approve(address to, uint256 tokenId, address auth, bool emitEvent) internal virtual override {
        if (to != address(0)) {
            address holder = _requireOwned(tokenId);
            if (!_allowed(to)) revert NotAgent(to);
            if (!_allowed(_msgSender())) revert NotAgent(_msgSender());
            if (holder != _msgSender() && !_allowed(holder)) revert NotAgent(holder);
        }
        super._approve(to, tokenId, auth, emitEvent);
    }

    function _setApprovalForAll(address owner, address operator, bool approved) internal virtual override {
        if (approved) {
            if (!_allowed(operator)) revert NotAgent(operator);
            if (!_allowed(owner)) revert NotAgent(owner);
        }
        super._setApprovalForAll(owner, operator, approved);
    }
}
```

When the holder is the caller, the check of the holder in `_update` and in
`_approve` is covered by the check of the caller. In `_setApprovalForAll`, the
caller is the owner. The token exposes no function besides those of ERC-721,
so rules 6 and 8 hold.

## Security Considerations

**The registry is the trust root.** Whoever controls the registry decides who
may hold every token that relies on it, and so does whoever can upgrade it: a
fixed registry address behind an upgradeable proxy fixes nothing. A token
behind an upgradeable proxy can lose every rule at its next upgrade; its
upgrade authority is part of the trust root too.

**Venues are the widest door.** A venue can deliver a token to any recognised
account and can hold tokens. A dishonest or faulty venue can therefore move
every token approved or entrusted to it, and an account approved as a venue
whose code can change, or that has no code, is a complete bypass. Removing a
venue at once also strands the tokens it holds in escrow.

**What a freeze stops.** A freeze stops the holder's own tokens, and every
approval it or its operators granted, from being used. It does not stop a
venue from delivering a token the frozen agent had placed in its escrow.
Approvals granted before the freeze survive it and become usable again when
the holder is unfrozen; holders and registries may clear them first.

**Liveness.** Every movement makes up to six calls to the registry, and a
grant of an approval up to six. The calls are read-only, so the registry
cannot re-enter the token, but a registry that reverts, runs out of gas or is
paused blocks every token that relies on it. Rule 6 forbids a way around this,
by design. Clearing an approval does not depend on the registry.

**Frozen tokens.** A token whose holder is revoked for good never moves again.
The proposal offers no recovery, by design: recovery would need the privileged
transfer that rules 6 and 8 forbid.

**What the rules cannot prevent.** The rules stop an account that the registry
does not recognise from receiving, moving or being approved for the token
directly. They cannot stop a recognised account from wrapping the token,
issuing claims on it, or handing over control of itself, for instance a smart
account whose owner key can change, or an account a human controls; a promise
on a token can be sold off chain. How strongly an account is shown to be an
agent is the registry's concern, and hardware attestation, its usual basis,
has been forged by attackers with physical access to the machine.

**Content is data.** A token's name, symbol and metadata are written by
whoever minted it. Agents should treat them as untrusted input and never as
instructions.

**Reentrancy.** `safeTransferFrom` calls `onERC721Received` on the recipient
after the registry checks. Every nested movement is checked again. Venues that
hold tokens should follow the checks-effects-interactions order.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
