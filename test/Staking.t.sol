// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721AgentOnly} from "../src/ERC721AgentOnly.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AgentStaking} from "../src/AgentStaking.sol";
import {AgentOnlyBase} from "./AgentOnly.t.sol";

contract StakingTest is AgentOnlyBase {
    AgentStaking staking;
    address distributor = address(0xD15);
    uint64 constant WEEK = 7 days;

    function setUp() public override {
        super.setUp();
        staking = new AgentStaking(nft, usdc, distributor, WEEK);
        _venue(address(staking));
        usdc.mint(distributor, 1_000_000 ether);
        vm.prank(distributor);
        usdc.approve(address(staking), type(uint256).max);
    }

    function _stake(uint256 pk, AgentAccount acc, uint256 id) internal {
        _do(pk, acc, address(nft), abi.encodeCall(nft.approve, (address(staking), id)));
        _do(pk, acc, address(staking), abi.encodeCall(staking.stake, (id)));
    }

    function _fund(uint256 amount) internal {
        vm.prank(distributor);
        staking.notifyRewardAmount(amount);
    }

    function test_StakeEarnUnstake() public {
        uint256 id = _mint(K1, acc1);
        _stake(K1, acc1, id);
        assertEq(nft.ownerOf(id), address(staking));
        _fund(7_000 ether);
        vm.warp(block.timestamp + WEEK);
        uint256 before = usdc.balanceOf(address(acc1));
        _do(K1, acc1, address(staking), abi.encodeCall(staking.unstake, (id)));
        assertEq(nft.ownerOf(id), address(acc1));
        assertApproxEqAbs(usdc.balanceOf(address(acc1)) - before, 7_000 ether, 1e6); // rounding dust only
    }

    function test_RewardsSplitBetweenStakes() public {
        uint256 a = _mint(K1, acc1);
        uint256 b = _mint(K2, acc2);
        uint256 c = _mint(K2, acc2);
        _stake(K1, acc1, a);
        _fund(7_000 ether);
        vm.warp(block.timestamp + 1 days); // agent 1 alone: 1,000
        _stake(K2, acc2, b);
        _stake(K2, acc2, c);
        vm.warp(block.timestamp + 6 days); // three stakes share 6,000: 2,000 per NFT
        assertApproxEqAbs(staking.earned(address(acc1)), 3_000 ether, 1e6);
        assertApproxEqAbs(staking.earned(address(acc2)), 4_000 ether, 1e6);
        vm.warp(block.timestamp + 30 days); // the stream has ended
        assertApproxEqAbs(staking.earned(address(acc1)), 3_000 ether, 1e6);
    }

    function test_OnlyTheStakerGetsTheNftBack() public {
        uint256 id = _mint(K1, acc1);
        _stake(K1, acc1, id);
        vm.prank(vm.addr(K2));
        vm.expectRevert(AgentStaking.NotStaker.selector);
        acc2.execute(address(staking), 0, abi.encodeCall(staking.unstake, (id)));
        vm.prank(human);
        vm.expectRevert(AgentStaking.NotStaker.selector);
        staking.unstake(id);
        // Nor can anyone stake a token it does not hold.
        uint256 other = _mint(K1, acc1);
        vm.prank(vm.addr(K2));
        vm.expectRevert(AgentStaking.NotOwner.selector);
        acc2.execute(address(staking), 0, abi.encodeCall(staking.stake, (other)));
    }

    function test_FrozenAgentNftStaysStakedUntilUnfrozen() public {
        uint256 id = _mint(K1, acc1);
        _stake(K1, acc1, id);
        vm.prank(SPONSOR1);
        reg.setFrozen(1, true);
        vm.prank(vm.addr(K1));
        vm.expectRevert(AgentAccount.NotKey.selector);
        acc1.execute(address(staking), 0, abi.encodeCall(staking.unstake, (id)));
        vm.prank(SPONSOR1);
        reg.setFrozen(1, false);
        _do(K1, acc1, address(staking), abi.encodeCall(staking.unstake, (id)));
        assertEq(nft.ownerOf(id), address(acc1));
    }

    function test_UnapprovedStakingContractCannotReceive() public {
        AgentStaking rogue = new AgentStaking(nft, usdc, distributor, WEEK);
        uint256 id = _mint(K1, acc1);
        vm.prank(vm.addr(K1));
        _expectNotAgent(address(rogue));
        acc1.execute(address(nft), 0, abi.encodeCall(nft.approve, (address(rogue), id)));
    }

    function test_OnlyDistributorAddsRewards() public {
        usdc.mint(human, 1 ether);
        vm.startPrank(human);
        usdc.approve(address(staking), 1 ether);
        vm.expectRevert(AgentStaking.NotDistributor.selector);
        staking.notifyRewardAmount(1 ether);
        vm.stopPrank();
        vm.prank(distributor);
        vm.expectRevert(AgentStaking.RateTooLow.selector);
        staking.notifyRewardAmount(1); // less than one unit per second
    }

    function test_TopUpKeepsLeftover() public {
        uint256 id = _mint(K1, acc1);
        _stake(K1, acc1, id);
        _fund(7_000 ether);
        vm.warp(block.timestamp + 3 days); // 3,000 paid out, 4,000 left
        _fund(3_000 ether); // 7,000 over a new week
        vm.warp(block.timestamp + WEEK);
        assertApproxEqAbs(staking.earned(address(acc1)), 10_000 ether, 1e6);
    }
}
