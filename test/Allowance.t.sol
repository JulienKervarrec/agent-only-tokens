// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AgentAllowance} from "../src/AgentAllowance.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AgentOnlyBase, MockUSDC} from "./AgentOnly.t.sol";
import {IUSDC} from "./X402.t.sol";

/// A token that keeps 1% of every transfer.
contract FeeToken is MockUSDC {
    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0)) return super._update(from, to, value);
        uint256 fee = value / 100;
        super._update(from, address(0xFEE), fee);
        super._update(from, to, value - fee);
    }
}

/// Step 3.1: the budget sits where the money is. An allowance pays the agent's account at most a
/// fixed amount per period; the account holds only what it drew, and that is all the agent can
/// spend, in x402 or otherwise, whatever its key signs and however often its machine restarts.
contract AllowanceTest is AgentOnlyBase {
    AgentAllowance box;
    IUSDC realUsdc;
    address constant SIGNATURE_CHECKER = 0x00000000000000000000000000000000005167C4;
    address merchant = address(0x5E11);
    uint128 constant LIMIT = 5e6; // 5 USDC
    uint64 constant DAY = 1 days;
    uint256 id;

    bytes32 constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    function setUp() public override {
        super.setUp();
        vm.etch(
            SIGNATURE_CHECKER, vm.parseJsonBytes(vm.readFile("test/usdc/SignatureChecker.json"), ".deployedBytecode")
        );
        realUsdc = IUSDC(deployCode("test/usdc/FiatTokenV2_2.json"));
        realUsdc.initialize("USD Coin", "USDC", "USD", 6, address(this), address(this), address(this), address(this));
        realUsdc.initializeV2("USD Coin");
        realUsdc.initializeV2_1(address(0xdead));
        realUsdc.initializeV2_2(new address[](0), "USDC");
        realUsdc.configureMinter(address(this), type(uint256).max);
        realUsdc.mint(SPONSOR1, 100e6);

        box = new AgentAllowance();
        vm.startPrank(SPONSOR1);
        IERC20(address(realUsdc)).approve(address(box), type(uint256).max);
        id = box.open(address(acc1), IERC20(address(realUsdc)), LIMIT, DAY, 100e6);
        vm.stopPrank();
    }

    function _draw(uint256 pk, uint256 amount) internal {
        _do(pk, acc1, address(box), abi.encodeCall(box.draw, (id, amount)));
    }

    function _pay(uint256 pk, uint256 value, bytes32 nonce) internal {
        bytes32 structHash = keccak256(
            abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, address(acc1), merchant, value, 0, NOW + 60, nonce)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", realUsdc.DOMAIN_SEPARATOR(), structHash));
        bytes memory sig = _sign(pk, acc1.messageDigest(digest));
        realUsdc.transferWithAuthorization(address(acc1), merchant, value, 0, NOW + 60, nonce, sig);
    }

    function pay(uint256 pk, uint256 value, bytes32 nonce) external {
        _pay(pk, value, nonce);
    }

    function test_TheAccountDrawsUpToTheLimitEachPeriod() public {
        assertEq(box.available(id), LIMIT);
        _draw(K1, 2e6);
        _draw(K1, 3e6);
        assertEq(realUsdc.balanceOf(address(acc1)), LIMIT);
        assertEq(box.available(id), 0);
        vm.expectRevert(abi.encodeWithSelector(AgentAllowance.OverLimit.selector, 0));
        _draw(K1, 1);
        skip(DAY);
        assertEq(box.available(id), LIMIT);
        _draw(K1, LIMIT);
        assertEq(realUsdc.balanceOf(address(acc1)), 2 * LIMIT);
        // The new period has its own limit, spent like the first.
        assertEq(box.available(id), 0);
        vm.expectRevert(abi.encodeWithSelector(AgentAllowance.OverLimit.selector, 0));
        _draw(K1, 1);
        assertEq(box.allowance(id).balance, 100e6 - 2 * LIMIT);
    }

    function test_OnlyTheAccountDrawsAndOnlyToItself() public {
        address[3] memory others = [SPONSOR1, vm.addr(K1), human];
        for (uint256 i; i < 3; ++i) {
            vm.prank(others[i]);
            vm.expectRevert(AgentAllowance.NotAccount.selector);
            box.draw(id, 1);
        }
        // Another agent's account cannot draw either.
        vm.expectRevert(AgentAllowance.NotAccount.selector);
        _do(K2, acc2, address(box), abi.encodeCall(box.draw, (id, 1)));
    }

    /// The x402 payment the account signs is checked by USDC against what the account holds:
    /// a misled agent can spend what it drew, and nothing more.
    function test_AMisledAgentSpendsAtMostWhatItDrew() public {
        _draw(K1, LIMIT);
        _pay(K1, 4e6, keccak256("a"));
        assertEq(realUsdc.balanceOf(merchant), 4e6);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        this.pay(K1, 2e6, keccak256("b"));
        vm.expectRevert(abi.encodeWithSelector(AgentAllowance.OverLimit.selector, 0));
        _draw(K1, 1);
        assertEq(realUsdc.balanceOf(merchant), 4e6);
    }

    /// The limit is the account's, not the key's: a restart with a new key does not reset it.
    function test_ANewKeyDoesNotResetTheBudget() public {
        _draw(K1, LIMIT);
        uint256 k1b = 0x0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b;
        _enroll(reg, SPONSOR1, 1, vm.addr(k1b), 0);
        vm.expectRevert(abi.encodeWithSelector(AgentAllowance.OverLimit.selector, 0));
        _draw(k1b, 1);
        vm.expectRevert(AgentAccount.NotKey.selector);
        _draw(K1, 1);
        skip(DAY);
        _draw(k1b, LIMIT);
        assertEq(realUsdc.balanceOf(address(acc1)), 2 * LIMIT);
    }

    function test_TheSponsorClosesAndTakesTheRestAtAnyTime() public {
        _draw(K1, 1e6);
        vm.prank(human);
        vm.expectRevert(AgentAllowance.NotSponsor.selector);
        box.close(id);
        vm.expectRevert(AgentAllowance.NotSponsor.selector);
        _do(K1, acc1, address(box), abi.encodeCall(box.close, (id)));
        vm.prank(SPONSOR1);
        box.close(id);
        assertEq(realUsdc.balanceOf(SPONSOR1), 99e6);
        assertEq(box.available(id), 0);
        vm.expectRevert(AgentAllowance.NotAccount.selector);
        _draw(K1, 1);
    }

    function test_OnlyTheSponsorAddsFundsAndTheTermsStay() public {
        realUsdc.mint(human, 10e6);
        vm.startPrank(human);
        IERC20(address(realUsdc)).approve(address(box), 10e6);
        vm.expectRevert(AgentAllowance.NotSponsor.selector);
        box.deposit(id, 10e6);
        vm.stopPrank();
        realUsdc.mint(SPONSOR1, 10e6);
        vm.prank(SPONSOR1);
        box.deposit(id, 10e6);
        assertEq(box.allowance(id).balance, 110e6);
        assertEq(box.available(id), LIMIT);
    }

    function test_BadTermsAreRefused() public {
        IERC20 t = IERC20(address(realUsdc));
        vm.startPrank(SPONSOR1);
        vm.expectRevert(AgentAllowance.BadTerms.selector);
        box.open(address(0), t, LIMIT, DAY, 0);
        vm.expectRevert(AgentAllowance.BadTerms.selector);
        box.open(address(acc1), IERC20(address(0)), LIMIT, DAY, 0);
        vm.expectRevert(AgentAllowance.BadTerms.selector);
        box.open(address(acc1), t, 0, DAY, 0);
        vm.expectRevert(AgentAllowance.BadTerms.selector);
        box.open(address(acc1), t, LIMIT, 0, 0);
        vm.stopPrank();
    }

    function test_AvailableNeverExceedsTheBalance() public {
        vm.startPrank(SPONSOR1);
        uint256 small = box.open(address(acc1), IERC20(address(realUsdc)), LIMIT, DAY, 0);
        vm.stopPrank();
        assertEq(box.available(small), 0);
        realUsdc.mint(SPONSOR1, 1e6);
        vm.prank(SPONSOR1);
        box.deposit(small, 1e6);
        assertEq(box.available(small), 1e6);
    }

    function test_AFeeTokenIsCreditedWhatArrives() public {
        FeeToken fee = new FeeToken();
        fee.mint(SPONSOR1, 1000);
        vm.startPrank(SPONSOR1);
        fee.approve(address(box), 1000);
        uint256 f = box.open(address(acc1), IERC20(address(fee)), 2000, DAY, 1000);
        vm.stopPrank();
        assertEq(box.allowance(f).balance, 990);
        assertEq(box.available(f), 990);
        _do(K1, acc1, address(box), abi.encodeCall(box.draw, (f, 990)));
        assertEq(box.allowance(f).balance, 0);
    }

    /// Whatever two draws the agent tries in one period, at most the limit comes out.
    function testFuzz_NeverMoreThanTheLimitInAPeriod(uint128 a, uint128 b, uint32 later) public {
        a = uint128(bound(a, 0, 2 * LIMIT));
        b = uint128(bound(b, 0, 2 * LIMIT));
        later = uint32(bound(later, 0, DAY - 1));
        uint256 before = realUsdc.balanceOf(address(acc1));
        try this.drawAs(K1, a) {} catch {}
        skip(later);
        try this.drawAs(K1, b) {} catch {}
        assertLe(realUsdc.balanceOf(address(acc1)) - before, LIMIT);
    }

    function drawAs(uint256 pk, uint256 amount) external {
        _draw(pk, amount);
    }
}
