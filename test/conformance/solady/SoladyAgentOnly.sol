// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC721} from "solady/tokens/ERC721.sol";
import {IAgentRegistry} from "../../../src/IAgentRegistry.sol";
import {IERC721AgentOnly} from "../../../src/IERC721AgentOnly.sol";

/// @notice Agent-Only ERC-721 on Solady. The caller is always `msg.sender` (no ERC-2771).
/// @dev Solady entry points and where the rules are enforced:
/// - transferFrom / safeTransferFrom (inlined), _mint, _safeMint, _mintAndSetExtraDataUnchecked,
///   _transfer, _safeTransfer, _burn: all call `_beforeTokenTransfer` (rules 2, 3, 4, 7, 8).
///   Rule 8 is re-checked there because `_transfer(address(0), ..)` and `_burn(id)` skip
///   Solady's authorisation, and `_mintAndSetExtraDataUnchecked` skips its existence check.
/// - approve -> _approve(msg.sender, ..); internal _approve(account, id) -> _approve(0, ..) (rule 5).
/// - Solady's setApprovalForAll is inlined and does NOT call _setApprovalForAll: rerouted here.
/// The enforcing overrides are not `virtual`, so a derived contract cannot drop them (rule 6).
abstract contract SoladyAgentOnly is ERC721, IERC721AgentOnly {
    error ZeroRegistry();
    error CallerNotRecognised(address caller);
    error RecipientNotRecognised(address recipient);
    error RecipientNotCaller(address recipient);
    error OperatorNotRecognised(address operator);
    error HolderNotRecognised(address holder);

    /// Rule 6: fixed for the life of the token.
    IAgentRegistry private immutable _registry;

    constructor(IAgentRegistry registry_) {
        if (address(registry_) == address(0)) revert ZeroRegistry(); // further restriction
        _registry = registry_;
    }

    function agentRegistry() external view returns (IAgentRegistry) {
        return _registry;
    }

    /// Rule 1: IERC721AgentOnly (0x0d1cfcae), plus ERC-165 / ERC-721 / Metadata from Solady.
    function supportsInterface(bytes4 id) public view virtual override returns (bool) {
        return id == type(IERC721AgentOnly).interfaceId || super.supportsInterface(id);
    }

    /// Recognised = isAgent or isVenue. Nothing else is consulted (no code / identity checks).
    function _isRecognised(address a) internal view returns (bool) {
        return _registry.isAgent(a) || _registry.isVenue(a);
    }

    /// Every mint, transfer and burn. `from == 0` is a mint, `to == 0` a burn.
    function _beforeTokenTransfer(address from, address to, uint256 id) internal view override {
        address caller = msg.sender;
        bool callerIsVenue = _registry.isVenue(caller);
        // Rule 2: the caller of any mint, transfer or burn must be recognised.
        if (!callerIsVenue && !_registry.isAgent(caller)) revert CallerNotRecognised(caller);
        if (from == address(0)) {
            // Rule 8: a mint must not change the holder of an existing token.
            if (_exists(id)) revert TokenAlreadyExists();
        } else {
            address holder = _ownerOf(id); // "holder" = ownerOf, not the `from` argument
            if (holder == address(0)) revert TokenDoesNotExist();
            // Rule 8: the caller must be the holder, the approved address or an operator.
            if (!_isApprovedOrOwner(caller, id)) revert NotOwnerNorApproved();
            // Rule 7: the holder must be recognised (already shown by rule 2 if it is the caller).
            if (holder != caller && !_isRecognised(holder)) revert HolderNotRecognised(holder);
        }
        if (to != address(0) && to != caller) {
            // Rule 4: outside a venue, the recipient pulls (recipient == caller).
            if (!callerIsVenue) revert RecipientNotCaller(to);
            // Rule 3: the recipient must be recognised (already true when to == caller).
            if (!_isRecognised(to)) revert RecipientNotRecognised(to);
        }
    }

    /// Rule 5 (approved address). Reached by public `approve` (by = msg.sender) and by
    /// internal `_approve(account, id)` (by = 0). Clearing makes no registry call.
    function _approve(address by, address account, uint256 id) internal override {
        if (account != address(0)) {
            address holder = _ownerOf(id);
            if (holder == address(0)) revert TokenDoesNotExist();
            // Rules 6 and 8 for grants: `by = 0` skips Solady's check, so the caller must be
            // the holder or its operator (Solady checks `by` itself when it is non-zero).
            if (by == address(0) && holder != msg.sender && !isApprovedForAll(holder, msg.sender)) {
                revert NotOwnerNorApproved();
            }
            _checkGrant(account, holder, by);
        }
        super._approve(by, account, id);
    }

    /// Rule 5 (operator). Solady's public version is inlined, so reroute it.
    function setApprovalForAll(address operator, bool isApproved) public override {
        _setApprovalForAll(msg.sender, operator, isApproved);
    }

    /// Rule 5: for an operator, the "holder" is the owner of the tokens, `by`.
    function _setApprovalForAll(address by, address operator, bool isApproved) internal override {
        if (isApproved) _checkGrant(operator, by, address(0));
        super._setApprovalForAll(by, operator, isApproved);
    }

    /// Rule 5: approved account, caller and holder must all be recognised (up to 6 calls).
    /// Further restriction: a different granter `by` passed by derived code must be too.
    function _checkGrant(address account, address holder, address by) private view {
        if (!_isRecognised(account)) revert OperatorNotRecognised(account);
        if (!_isRecognised(msg.sender)) revert CallerNotRecognised(msg.sender);
        if (holder != msg.sender && !_isRecognised(holder)) revert HolderNotRecognised(holder);
        if (by != address(0) && by != msg.sender && by != holder && !_isRecognised(by)) {
            revert CallerNotRecognised(by);
        }
    }
}
