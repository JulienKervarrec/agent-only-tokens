// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IAgentRegistry} from "./IAgentRegistry.sol";
import {IERC721AgentOnly} from "./IERC721AgentOnly.sol";

/// @title A classic ERC-721, restricted to agents.
/// @notice Unaudited draft. Three rules added to a standard ERC-721:
/// 1. only an agent or an approved venue can hold a token or be approved for it;
/// 2. only an agent or an approved venue can trigger a movement;
/// 3. an agent only receives a token if it pulls it itself (no unsolicited token).
/// A token whose holder is no longer recognised (frozen, expired, revoked) does not move.
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
        bool venue = agentRegistry.isVenue(caller);
        if (!venue && !agentRegistry.isAgent(caller)) revert NotAgent(caller);
        address from = _ownerOf(tokenId);
        if (from != address(0) && from != caller && !_allowed(from)) revert NotAgent(from);
        if (to != address(0)) {
            if (!_allowed(to)) revert NotAgent(to);
            if (!venue && to != caller) revert NotPulledByRecipient();
        }
        return super._update(to, tokenId, auth);
    }

    function _approve(address to, uint256 tokenId, address auth, bool emitEvent) internal virtual override {
        if (to != address(0) && !_allowed(to)) revert NotAgent(to);
        super._approve(to, tokenId, auth, emitEvent);
    }

    function _setApprovalForAll(address owner, address operator, bool approved) internal virtual override {
        if (approved && !_allowed(operator)) revert NotAgent(operator);
        super._setApprovalForAll(owner, operator, approved);
    }
}
