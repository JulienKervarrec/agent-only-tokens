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
    /// Repayments waiting for their lender, per currency.
    mapping(IERC20 => mapping(address => uint256)) public owed;

    // Loans cannot be enumerated on-chain: these events are how an agent finds offers to fund.
    event Offered(
        IERC721 indexed nft,
        uint256 indexed id,
        address indexed borrower,
        IERC20 currency,
        uint256 principal,
        uint256 repayAmount,
        uint64 duration
    );
    event Cancelled(IERC721 indexed nft, uint256 indexed id);
    event Funded(IERC721 indexed nft, uint256 indexed id, address indexed lender, uint64 due);
    event Repaid(IERC721 indexed nft, uint256 indexed id);
    event Claimed(IERC721 indexed nft, uint256 indexed id, address indexed lender);

    error NotParty();
    error BadState();
    error NotDue();
    error TermsChanged();

    /// The borrower deposits its token and publishes its terms.
    function offer(IERC721 nft, uint256 id, IERC20 currency, uint256 principal, uint256 repayAmount, uint64 duration)
        external
        nonReentrant
    {
        if (loans[nft][id].borrower != address(0)) revert BadState();
        loans[nft][id] = Loan(msg.sender, address(0), currency, principal, repayAmount, duration, 0);
        emit Offered(nft, id, msg.sender, currency, principal, repayAmount, duration);
        nft.transferFrom(msg.sender, address(this), id);
    }

    /// As long as nobody has funded it, the borrower can take its token back.
    function cancel(IERC721 nft, uint256 id) external nonReentrant {
        Loan memory l = loans[nft][id];
        if (l.borrower != msg.sender) revert NotParty();
        if (l.lender != address(0)) revert BadState();
        delete loans[nft][id];
        emit Cancelled(nft, id);
        nft.transferFrom(address(this), msg.sender, id);
    }

    /// The lender states the terms it agreed to: the borrower cannot change them between
    /// the lender's decision and its transaction.
    function fund(IERC721 nft, uint256 id, IERC20 currency, uint256 principal, uint256 repayAmount, uint64 duration)
        external
        nonReentrant
    {
        Loan storage l = loans[nft][id];
        if (l.borrower == address(0) || l.lender != address(0)) revert BadState();
        if (l.currency != currency || l.principal != principal || l.repay != repayAmount || l.duration != duration) {
            revert TermsChanged();
        }
        l.lender = msg.sender;
        l.due = uint64(block.timestamp) + l.duration;
        emit Funded(nft, id, msg.sender, l.due);
        l.currency.safeTransferFrom(msg.sender, l.borrower, l.principal);
    }

    /// Allowed even after the due date, as long as the lender has not claimed. The repayment
    /// is kept here for the lender to `withdraw`: a lender that cannot or will not receive the
    /// currency cannot make a repayment fail and then claim the token.
    function repay(IERC721 nft, uint256 id) external nonReentrant {
        Loan memory l = loans[nft][id];
        if (l.borrower != msg.sender) revert NotParty();
        if (l.lender == address(0)) revert BadState();
        delete loans[nft][id];
        owed[l.currency][l.lender] += l.repay;
        emit Repaid(nft, id);
        l.currency.safeTransferFrom(msg.sender, address(this), l.repay);
        nft.transferFrom(address(this), msg.sender, id);
    }

    /// A lender collects what its borrowers have repaid in `currency`.
    function withdraw(IERC20 currency) external nonReentrant {
        uint256 amount = owed[currency][msg.sender];
        owed[currency][msg.sender] = 0;
        currency.safeTransfer(msg.sender, amount);
    }

    function claim(IERC721 nft, uint256 id) external nonReentrant {
        Loan memory l = loans[nft][id];
        if (l.lender != msg.sender) revert NotParty();
        if (block.timestamp <= l.due) revert NotDue();
        delete loans[nft][id];
        emit Claimed(nft, id, msg.sender);
        nft.transferFrom(address(this), msg.sender, id);
    }
}
