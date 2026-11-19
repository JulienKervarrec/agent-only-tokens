// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IAgentRegistry} from "./IAgentRegistry.sol";
import {IERC1155AgentOnly} from "./IERC1155AgentOnly.sol";

/// @title A classic ERC-1155, restricted to agents: the ERC-1155 profile of the standard.
/// @notice Unaudited draft. The same three rules as ERC721AgentOnly, for every id of a batch:
/// only agents and approved venues hold, move or are approved; outside a venue the recipient
/// pulls; a holder that is no longer recognised does not move. ERC-1155 has no approval for a
/// single token, so `setApprovalForAll` is the only grant.
abstract contract ERC1155AgentOnly is ERC1155, IERC1155AgentOnly {
    IAgentRegistry public immutable override agentRegistry;

    error NotAgent(address account);
    error NotPulledByRecipient();

    constructor(IAgentRegistry registry_) {
        agentRegistry = registry_;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC1155AgentOnly).interfaceId || super.supportsInterface(interfaceId);
    }

    function _allowed(address account) private view returns (bool) {
        return agentRegistry.isAgent(account) || agentRegistry.isVenue(account);
    }

    /// Every mint, transfer and burn, single or batch. The checks do not depend on the ids.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        virtual
        override
    {
        address caller = _msgSender();
        bool pull = to == caller;
        bool venue;
        if (pull) {
            if (!_allowed(caller)) revert NotAgent(caller);
        } else {
            venue = agentRegistry.isVenue(caller);
            if (!venue && !agentRegistry.isAgent(caller)) revert NotAgent(caller);
        }
        if (from != address(0) && from != caller && !_allowed(from)) revert NotAgent(from);
        if (!pull && to != address(0)) {
            if (!_allowed(to)) revert NotAgent(to);
            if (!venue) revert NotPulledByRecipient();
        }
        super._update(from, to, ids, values);
    }

    /// The owner and the operator must be recognised to grant; revoking is always free.
    function _setApprovalForAll(address owner, address operator, bool approved) internal virtual override {
        if (approved) {
            if (!_allowed(operator)) revert NotAgent(operator);
            if (!_allowed(owner)) revert NotAgent(owner);
        }
        super._setApprovalForAll(owner, operator, approved);
    }
}
