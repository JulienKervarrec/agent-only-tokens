// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {AgentLoan} from "../src/AgentLoan.sol";
import {MaybeFeeToken, PlainNft} from "./halmos/VenueProps.t.sol";

/// Found by the symbolic proof `check_RepaymentsAreAlwaysCovered` (step 6.1): in a currency
/// that keeps part of every transfer, the loan venue owed its lender more than it held.
contract LoanFeeTest is Test {
    address constant BORROWER = address(0xB0);
    address constant LENDER = address(0x1E);

    function _loan(uint256 fee) internal returns (AgentLoan loan, MaybeFeeToken money, PlainNft nft) {
        loan = new AgentLoan();
        money = new MaybeFeeToken(fee);
        nft = new PlainNft();
        nft.mint(BORROWER, 1);
        money.mint(LENDER, 100);
        money.mint(BORROWER, 200);
        vm.startPrank(BORROWER);
        nft.approve(address(loan), 1);
        loan.offer(IERC721(address(nft)), 1, IERC20(address(money)), 100, 110, 1 days);
        money.approve(address(loan), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(LENDER);
        money.approve(address(loan), 100);
        loan.fund(IERC721(address(nft)), 1, IERC20(address(money)), 100, 110, 1 days);
        vm.stopPrank();
    }

    function test_ARepaymentThatArrivesShortIsRefused() public {
        (AgentLoan loan,, PlainNft nft) = _loan(10); // 1% kept on each transfer
        vm.prank(BORROWER);
        vm.expectRevert(AgentLoan.ShortPayment.selector);
        loan.repay(IERC721(address(nft)), 1);
        assertEq(nft.ownerOf(1), address(loan)); // the loan stands; the lender can claim when due
    }

    function test_AFullRepaymentIsOwedAndPaidToTheLender() public {
        (AgentLoan loan, MaybeFeeToken money, PlainNft nft) = _loan(0);
        vm.prank(BORROWER);
        loan.repay(IERC721(address(nft)), 1);
        assertEq(loan.owed(IERC20(address(money)), LENDER), 110);
        vm.prank(LENDER);
        loan.withdraw(IERC20(address(money)));
        assertEq(money.balanceOf(LENDER), 110);
        assertEq(nft.ownerOf(1), BORROWER);
    }
}
