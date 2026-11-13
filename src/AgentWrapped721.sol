// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {ERC721Wrapper} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Wrapper.sol";
import {IAgentRegistry} from "./IAgentRegistry.sol";
import {ERC721AgentOnly} from "./ERC721AgentOnly.sol";

/// @title Agent-only wrapper for any existing NFT.
/// @notice Unaudited draft. The original NFT is held by this contract; an agent-only token with
/// the same id represents it. Built on OpenZeppelin's ERC721Wrapper.
/// @dev `unwrappable` is fixed at deployment. If true, the holder can withdraw the original NFT
/// to its own account: it is then a classic NFT again. If false, the original
/// NFT never leaves; a derived contract must provide the means to use it.
contract AgentWrapped721 is ERC721Wrapper, ERC721AgentOnly {
    bool public immutable unwrappable;

    error NotUnwrappable();
    error OnlyToSelf();

    constructor(
        IERC721 underlying_,
        IAgentRegistry registry_,
        bool unwrappable_,
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) ERC721Wrapper(underlying_) ERC721AgentOnly(registry_) {
        unwrappable = unwrappable_;
    }

    /// The original NFT can only be withdrawn to the account of the agent asking for it.
    function withdrawTo(address account, uint256[] memory tokenIds) public virtual override returns (bool) {
        if (!unwrappable) revert NotUnwrappable();
        if (account != _msgSender()) revert OnlyToSelf();
        return super.withdrawTo(account, tokenIds);
    }

    /// Metadata stays that of the original NFT.
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireOwned(tokenId);
        return IERC721Metadata(address(underlying())).tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721AgentOnly)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        virtual
        override(ERC721, ERC721AgentOnly)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _approve(address to, uint256 tokenId, address auth, bool emitEvent)
        internal
        virtual
        override(ERC721, ERC721AgentOnly)
    {
        super._approve(to, tokenId, auth, emitEvent);
    }

    function _setApprovalForAll(address owner, address operator, bool approved)
        internal
        virtual
        override(ERC721, ERC721AgentOnly)
    {
        super._setApprovalForAll(owner, operator, approved);
    }
}
