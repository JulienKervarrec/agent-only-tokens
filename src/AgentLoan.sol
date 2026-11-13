// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Collateralised loan between agents. Unaudited draft.
/// @dev The token is held here during the loan. On the way out, the token itself rejects
/// any recipient that is not an agent: this contract therefore cannot deliver it to a human.
contract AgentLoan is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Loan {
        address borrower;
        address lender; // address(0) until the loan is funded
        IERC20 currency;
        uint256 principal;
        uint256 repay;
        uint64 duration;
        uint64 due;
    }

    mapping(IERC721 => mapping(uint256 => Loan)) public loans;

    error NotParty();
    error BadState();
    error NotDue();

    /// The borrower deposits its token and publishes its terms.
    function offer(IERC721 nft, uint256 id, IERC20 currency, uint256 principal, uint256 repayAmount, uint64 duration)
        external
        nonReentrant
    {
        if (loans[nft][id].borrower != address(0)) revert BadState();
        loans[nft][id] = Loan(msg.sender, address(0), currency, principal, repayAmount, duration, 0);
        nft.transferFrom(msg.sender, address(this), id);
    }

    /// As long as nobody has funded it, the borrower can take its token back.
    function cancel(IERC721 nft, uint256 id) external nonReentrant {
        Loan memory l = loans[nft][id];
        if (l.borrower != msg.sender) revert NotParty();
        if (l.lender != address(0)) revert BadState();
        delete loans[nft][id];
        nft.transferFrom(address(this), msg.sender, id);
    }

    function fund(IERC721 nft, uint256 id) external nonReentrant {
        Loan storage l = loans[nft][id];
        if (l.borrower == address(0) || l.lender != address(0)) revert BadState();
        l.lender = msg.sender;
        l.due = uint64(block.timestamp) + l.duration;
        l.currency.safeTransferFrom(msg.sender, l.borrower, l.principal);
    }

    /// Allowed even after the due date, as long as the lender has not claimed.
    function repay(IERC721 nft, uint256 id) external nonReentrant {
        Loan memory l = loans[nft][id];
        if (l.borrower != msg.sender) revert NotParty();
        if (l.lender == address(0)) revert BadState();
        delete loans[nft][id];
        l.currency.safeTransferFrom(msg.sender, l.lender, l.repay);
        nft.transferFrom(address(this), msg.sender, id);
    }

    function claim(IERC721 nft, uint256 id) external nonReentrant {
        Loan memory l = loans[nft][id];
        if (l.lender != msg.sender) revert NotParty();
        if (block.timestamp <= l.due) revert NotDue();
        delete loans[nft][id];
        nft.transferFrom(address(this), msg.sender, id);
    }
}
