// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {AgentOnlyBase} from "../AgentOnly.t.sol";
import {AgentAccount} from "../../src/AgentAccount.sol";
import {DualKey} from "../../src/experimental/DualKey.sol";

/// An agent whose session key is held by two machines from two makers.
contract DualKeyTest is AgentOnlyBase {
    uint256 constant KA = 0xA0A0; // the key created in the Intel machine
    uint256 constant KB = 0xB0B0; // the key created in the second machine
    DualKey dual;
    AgentAccount acc3;

    function setUp() public override {
        super.setUp();
        dual = new DualKey(vm.addr(KA), vm.addr(KB));
        vm.deal(address(0x103), 1 ether);
        _enroll(reg, address(0x103), 3, address(dual), BOND);
        acc3 = AgentAccount(payable(reg.accountOf(3)));
    }

    function _order(bytes memory call) internal view returns (bytes memory data, bytes32 d) {
        data = abi.encodeCall(AgentAccount.execute, (address(nft), 0, call));
        d = dual.actDigest(address(acc3), data, dual.nonce(), FAR);
    }

    function test_BothSignTheAgentActs() public {
        (bytes memory data, bytes32 d) = _order(abi.encodeCall(nft.mint, (bytes32(uint256(7)))));
        uint256 id = abi.decode(
            abi.decode(dual.act(address(acc3), data, FAR, _sign(KA, d), _sign(KB, d)), (bytes)), (uint256)
        );
        assertEq(nft.ownerOf(id), address(acc3));
    }

    function test_OneMachineAloneCannotAct() public {
        (bytes memory data, bytes32 d) = _order(abi.encodeCall(nft.mint, (bytes32(uint256(7)))));
        vm.expectRevert(DualKey.NotBoth.selector);
        dual.act(address(acc3), data, FAR, _sign(KA, d), _sign(KA, d));
        vm.expectRevert(DualKey.NotBoth.selector);
        dual.act(address(acc3), data, FAR, _sign(KB, d), _sign(KB, d));
        // And neither key can call the account directly.
        vm.prank(vm.addr(KA));
        vm.expectRevert(AgentAccount.NotKey.selector);
        acc3.execute(address(nft), 0, abi.encodeCall(nft.mint, (bytes32(uint256(7)))));
    }

    function test_AnOrderRunsOnce() public {
        (bytes memory data, bytes32 d) = _order(abi.encodeCall(nft.mint, (bytes32(uint256(7)))));
        bytes memory a = _sign(KA, d);
        bytes memory b = _sign(KB, d);
        dual.act(address(acc3), data, FAR, a, b);
        vm.expectRevert(DualKey.NotBoth.selector);
        dual.act(address(acc3), data, FAR, a, b);
    }

    function test_ExpiredOrderIsRefused() public {
        bytes memory data = abi.encodeCall(AgentAccount.execute, (address(nft), 0, ""));
        bytes32 d = dual.actDigest(address(acc3), data, 0, uint64(block.timestamp - 1));
        vm.expectRevert(DualKey.Expired.selector);
        dual.act(address(acc3), data, uint64(block.timestamp - 1), _sign(KA, d), _sign(KB, d));
    }

    function test_BadKeysAreRefused() public {
        vm.expectRevert(DualKey.BadKeys.selector);
        new DualKey(vm.addr(KA), vm.addr(KA));
        vm.expectRevert(DualKey.BadKeys.selector);
        new DualKey(address(0), vm.addr(KB));
        vm.expectRevert(DualKey.BadKeys.selector);
        new DualKey(vm.addr(KA), address(0));
    }

    function test_DualKeySignsAsAContract() public view {
        bytes32 h = keccak256("an order");
        bytes32 d = dual.messageDigest(h);
        assertEq(dual.isValidSignature(h, bytes.concat(_sign(KA, d), _sign(KB, d))), bytes4(0x1626ba7e));
        assertEq(dual.isValidSignature(h, bytes.concat(_sign(KA, d), _sign(KA, d))), bytes4(0xffffffff));
        assertEq(dual.isValidSignature(h, _sign(KA, d)), bytes4(0xffffffff));
    }

    /// Today's limit: the account checks signatures as from a plain key, so an x402 payment
    /// signed by the two keys is refused. ERC-1271 support for a contract key is the change needed.
    function test_TodayTheAccountCannotSignWithADualKey() public view {
        bytes32 h = keccak256("an x402 payment");
        bytes32 d = acc3.messageDigest(h);
        assertEq(acc3.isValidSignature(h, bytes.concat(_sign(KA, d), _sign(KB, d))), bytes4(0xffffffff));
    }
}
