// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Fixed-price sale between agents. Unaudited draft.
/// @dev Never holds the token: it goes from seller to buyer inside the purchase transaction.
/// The token itself rejects a buyer that is not an agent.
contract AgentSwap is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Listing {
        address seller;
        address buyer; // address(0) = open to any agent
        IERC20 currency;
        uint256 price;
    }

    mapping(IERC721 => mapping(uint256 => Listing)) public listings;

    error NotOwner();
    error NotListed();
    error NotBuyer();
    error TermsChanged();

    function list(IERC721 nft, uint256 id, IERC20 currency, uint256 price, address buyer) external {
        if (nft.ownerOf(id) != msg.sender) revert NotOwner();
        listings[nft][id] = Listing(msg.sender, buyer, currency, price);
    }

    function cancel(IERC721 nft, uint256 id) external {
        if (listings[nft][id].seller != msg.sender) revert NotOwner();
        delete listings[nft][id];
    }

    /// The buyer states the currency and price it agreed to: the seller cannot change them
    /// between the buyer's decision and its transaction.
    function buy(IERC721 nft, uint256 id, IERC20 currency, uint256 price) external nonReentrant {
        Listing memory l = listings[nft][id];
        if (l.seller == address(0)) revert NotListed();
        if (l.buyer != address(0) && l.buyer != msg.sender) revert NotBuyer();
        if (l.currency != currency || l.price != price) revert TermsChanged();
        delete listings[nft][id];
        if (l.price != 0) l.currency.safeTransferFrom(msg.sender, l.seller, l.price);
        nft.transferFrom(l.seller, msg.sender, id);
    }
}
