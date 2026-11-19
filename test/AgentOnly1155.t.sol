// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IAgentRegistry} from "../src/IAgentRegistry.sol";
import {ERC1155AgentOnly} from "../src/ERC1155AgentOnly.sol";
import {AgentOnlyBase} from "./AgentOnly.t.sol";
import {Reference1155} from "./conformance/Reference1155.t.sol";

/// The ERC-1155 profile with real agent accounts and our registry: an account must answer the
/// ERC-1155 receiver calls, or no ERC-1155 could ever reach it.
contract AgentOnly1155Test is AgentOnlyBase {
    Reference1155 multi;

    function setUp() public override {
        super.setUp();
        multi = new Reference1155(IAgentRegistry(address(reg)));
    }

    function test_AgentAccountsMintPullAndHumansCannotReceive() public {
        uint256 id = abi.decode(_do(K1, acc1, address(multi), abi.encodeCall(multi.mint, (10))), (uint256));
        assertEq(multi.balanceOf(address(acc1), id), 10);
        _do(K1, acc1, address(multi), abi.encodeCall(multi.setApprovalForAll, (address(acc2), true)));
        _do(
            K2,
            acc2,
            address(multi),
            abi.encodeCall(IERC1155.safeTransferFrom, (address(acc1), address(acc2), id, 4, ""))
        );
        assertEq(multi.balanceOf(address(acc2), id), 4);
        // Pushing to another agent, or sending to a human, is refused.
        vm.expectRevert(ERC1155AgentOnly.NotPulledByRecipient.selector);
        _do(
            K1,
            acc1,
            address(multi),
            abi.encodeCall(IERC1155.safeTransferFrom, (address(acc1), address(acc2), id, 1, ""))
        );
        vm.expectRevert(abi.encodeWithSelector(ERC1155AgentOnly.NotAgent.selector, human));
        _do(K1, acc1, address(multi), abi.encodeCall(multi.setApprovalForAll, (human, true)));
        // A frozen agent's units do not move, even with an approval given before.
        vm.prank(SPONSOR1);
        reg.setFrozen(1, true);
        vm.expectRevert(abi.encodeWithSelector(ERC1155AgentOnly.NotAgent.selector, address(acc1)));
        _do(
            K2,
            acc2,
            address(multi),
            abi.encodeCall(IERC1155.safeTransferFrom, (address(acc1), address(acc2), id, 1, ""))
        );
    }
}
