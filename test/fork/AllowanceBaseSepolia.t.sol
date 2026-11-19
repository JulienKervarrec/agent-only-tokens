// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AgentAllowance} from "../../src/AgentAllowance.sol";
import {AgentAccount} from "../../src/AgentAccount.sol";
import {AttestedAgentRegistry} from "../../src/AttestedAgentRegistry.sol";

/// Step 3.1 on a fork of Base Sepolia: an allowance in Circle's live USDC for the account of the
/// agent enrolled by hardware attestation (section 3.21). The agent draws through its real
/// account with whatever key the registry recognises today; it cannot spend more than it drew.
/// Skipped unless BASE_SEPOLIA_RPC is set.
contract AllowanceBaseSepoliaTest is Test {
    AttestedAgentRegistry constant REG = AttestedAgentRegistry(payable(0xE78420EDf016b1249F2F8664ab172240C43BaD52));
    AgentAccount constant ACCOUNT = AgentAccount(payable(0xD6eC25de098d6f23A8Bc180C1A95B8a1A5c238e7));
    IERC20 constant USDC = IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e);
    address constant SPONSOR = address(0x5905); // a fresh address, funded on the fork only
    address constant SHOP = address(0x5409);
    uint128 constant LIMIT = 1e6;

    bool forked;
    AgentAllowance box;
    uint256 id;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        forked = true;
        box = new AgentAllowance();
        deal(address(USDC), SPONSOR, 10e6);
        vm.startPrank(SPONSOR);
        USDC.approve(address(box), 10e6);
        id = box.open(address(ACCOUNT), USDC, LIMIT, 1 days, 10e6);
        vm.stopPrank();
    }

    /// The agent acts: the caller is set by the test to the key the registry recognises today.
    function _act(address target, bytes memory data) internal {
        ACCOUNT.execute(target, 0, data);
    }

    function test_TheRealAccountDrawsWithinTheLimitAndSpendsNoMore() public {
        vm.skip(!forked);
        assertTrue(REG.isAgent(address(ACCOUNT)));
        uint256 before = USDC.balanceOf(address(ACCOUNT));
        vm.startPrank(REG.keyOf(1));
        _act(address(box), abi.encodeCall(box.draw, (id, LIMIT)));
        assertEq(USDC.balanceOf(address(ACCOUNT)), before + LIMIT);
        vm.expectRevert(abi.encodeWithSelector(AgentAllowance.OverLimit.selector, 0));
        _act(address(box), abi.encodeCall(box.draw, (id, 1)));
        // An order the machine signs to pay more than was drawn: Circle's USDC refuses it.
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        _act(address(USDC), abi.encodeCall(USDC.transfer, (SHOP, before + LIMIT + 1)));
        _act(address(USDC), abi.encodeCall(USDC.transfer, (SHOP, before + LIMIT)));
        vm.stopPrank();
        assertEq(USDC.balanceOf(SHOP), before + LIMIT);
        assertEq(box.allowance(id).balance, 10e6 - LIMIT);
    }

    function test_AnotherKeyThanTheRegistrysCannotDraw() public {
        vm.skip(!forked);
        vm.prank(address(0xBAD));
        vm.expectRevert(AgentAccount.NotKey.selector);
        ACCOUNT.execute(address(box), 0, abi.encodeCall(box.draw, (id, 1)));
        vm.prank(address(0xBAD));
        vm.expectRevert(AgentAllowance.NotAccount.selector);
        box.draw(id, 1);
    }
}
