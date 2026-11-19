// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {AgentLoan} from "../../src/AgentLoan.sol";
import {AgentAllowance} from "../../src/AgentAllowance.sol";
import {AgentAccount} from "../../src/AgentAccount.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// A currency that may keep a share of every transfer (1% here), as some tokens do.
contract MaybeFeeToken is ERC20 {
    uint256 public immutable feePerMille;

    constructor(uint256 feePerMille_) ERC20("Money", "MNY") {
        feePerMille = feePerMille_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0) || feePerMille == 0) return super._update(from, to, value);
        uint256 fee = value * feePerMille / 1000;
        super._update(from, address(0xFEE), fee);
        super._update(from, to, value - fee);
    }
}

/// A plain NFT for the collateral: the loan venue works with any ERC-721.
contract PlainNft is ERC721("Plain", "PLN") {
    function mint(address to, uint256 id) external {
        _mint(to, id);
    }
}

/// Properties of the venues and of the allowance, proved with Halmos: every argument of a
/// `check_` function stands for all its values at once. Run with
/// `halmos --match-contract "LoanProps|AllowanceProps|AccountProps"`.
contract LoanProps is Test {
    address constant BORROWER = address(0xB0);
    address constant LENDER = address(0x1E);
    address constant OTHER = address(0x07);

    /// What the loan venue owes its lenders is always covered by what it holds: after an offer,
    /// a funding and a repayment of any amounts, in a currency with or without a fee, the venue
    /// holds at least what it owes, and the lender can withdraw it.
    function check_RepaymentsAreAlwaysCovered(uint64 principal, uint64 repayAmount, bool fee, uint8 who) public {
        AgentLoan loan = new AgentLoan();
        MaybeFeeToken money = new MaybeFeeToken(fee ? 10 : 0);
        PlainNft nft = new PlainNft();
        nft.mint(BORROWER, 1);
        money.mint(LENDER, principal);
        money.mint(BORROWER, uint256(repayAmount) * 2);
        vm.startPrank(BORROWER);
        nft.approve(address(loan), 1);
        loan.offer(IERC721(address(nft)), 1, IERC20(address(money)), principal, repayAmount, 1 days);
        money.approve(address(loan), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(LENDER);
        money.approve(address(loan), principal);
        loan.fund(IERC721(address(nft)), 1, IERC20(address(money)), principal, repayAmount, 1 days);
        vm.stopPrank();
        vm.prank(BORROWER);
        try loan.repay(IERC721(address(nft)), 1) {} catch {}
        assertLe(loan.owed(IERC20(address(money)), LENDER), money.balanceOf(address(loan)));
        // Whoever asks, a withdrawal never takes more than the venue holds, and never fails for
        // the lender it owes.
        address caller = who % 2 == 0 ? LENDER : OTHER;
        uint256 owed = loan.owed(IERC20(address(money)), caller);
        vm.prank(caller);
        loan.withdraw(IERC20(address(money)));
        assertEq(loan.owed(IERC20(address(money)), caller), 0);
        assertLe(owed, uint256(repayAmount));
    }
}

contract AllowanceProps is Test {
    address constant SPONSOR = address(0x5905);
    address constant ACCOUNT = address(0xACC);
    AgentAllowance box;
    MaybeFeeToken money;

    function _open(uint64 limit, uint64 deposit, bool fee) internal returns (uint256 id) {
        box = new AgentAllowance();
        money = new MaybeFeeToken(fee ? 10 : 0);
        money.mint(SPONSOR, deposit);
        vm.startPrank(SPONSOR);
        money.approve(address(box), deposit);
        id = box.open(ACCOUNT, IERC20(address(money)), limit, 1 days, deposit);
        vm.stopPrank();
    }

    /// Nobody but the account draws, whatever it asks.
    function check_OnlyTheAccountDraws(address caller, uint64 amount) public {
        vm.assume(caller != ACCOUNT);
        uint256 id = _open(1000, 1000, false);
        vm.prank(caller);
        (bool ok,) = address(box).call(abi.encodeCall(box.draw, (id, amount)));
        assert(!ok);
    }

    /// However two draws are sized and timed within one period, at most the limit leaves.
    function check_NeverMoreThanTheLimitInAPeriod(uint64 limit, uint64 first, uint64 second, uint32 gap) public {
        vm.assume(limit > 0 && gap < 1 days);
        uint256 id = _open(limit, type(uint64).max, false);
        uint256 start = block.timestamp;
        vm.prank(ACCOUNT);
        (bool ok1,) = address(box).call(abi.encodeCall(box.draw, (id, first)));
        vm.warp(start + gap);
        vm.prank(ACCOUNT);
        (bool ok2,) = address(box).call(abi.encodeCall(box.draw, (id, second)));
        assert((ok1 ? uint256(first) : 0) + (ok2 ? uint256(second) : 0) <= limit);
    }

    /// The allowance never promises more than it holds, even in a currency with a fee.
    function check_PromisesNoMoreThanItHolds(uint64 deposit, uint64 amount, bool fee) public {
        uint256 id = _open(type(uint64).max, deposit, fee);
        vm.prank(ACCOUNT);
        (bool ok,) = address(box).call(abi.encodeCall(box.draw, (id, amount)));
        ok;
        assert(box.allowance(id).balance <= money.balanceOf(address(box)));
    }
}

/// A registry stand-in that names one key for every agent.
contract OneKey {
    address public immutable key;

    constructor(address key_) {
        key = key_;
    }

    function keyOf(uint256) external view returns (address) {
        return key;
    }
}

/// The agent's account obeys its current key, and nobody else.
contract AccountProps is Test {
    /// Whoever calls, with whatever target, value and data: unless the caller is the key the
    /// registry names, `execute` and `executeBatch` refuse, and nothing leaves the account.
    function check_OnlyTheKeyMakesTheAccountAct(address key, address caller, address target, uint96 value) public {
        vm.assume(caller != key && caller != address(0));
        OneKey keys = new OneKey(key);
        AgentAccount impl = new AgentAccount();
        address account = Clones.cloneWithImmutableArgs(address(impl), abi.encode(address(keys), uint256(1)));
        vm.deal(account, value);
        vm.assume(caller != account);
        vm.prank(caller);
        (bool ok,) = account.call(abi.encodeCall(AgentAccount.execute, (target, value, "")));
        assert(!ok);
        AgentAccount.Call[] memory calls = new AgentAccount.Call[](1);
        calls[0] = AgentAccount.Call(target, value, "");
        vm.prank(caller);
        (ok,) = account.call(abi.encodeCall(AgentAccount.executeBatch, (calls)));
        assert(!ok);
        assert(account.balance == value);
    }
}
