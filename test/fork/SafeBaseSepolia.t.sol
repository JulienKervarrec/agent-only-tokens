// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {AttestedAgentRegistry} from "../../src/AttestedAgentRegistry.sol";
import {AgentSwap} from "../../src/AgentSwap.sol";

interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

interface ISafe {
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
    function getThreshold() external view returns (uint256);
    function VERSION() external view returns (string memory);
    function nonce() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function isOwner(address owner) external view returns (bool);
    function signedMessages(bytes32 messageHash) external view returns (uint256);
    function swapOwner(address prevOwner, address oldOwner, address newOwner) external;
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce_
    ) external view returns (bytes32);
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);
}

interface ISignMessageLib {
    function signMessage(bytes calldata data) external;
}

interface ISafeMessages {
    function getMessageHashForSafe(address safe, bytes memory message) external view returns (bytes32);
}

/// A real Safe as an attester, against the Safe contracts deployed on Base Sepolia, on a fork.
/// Skipped unless BASE_SEPOLIA_RPC is set:
///   BASE_SEPOLIA_RPC=https://sepolia.base.org forge test --match-path 'test/fork/*'
/// A Safe answers ERC-1271 through its fallback handler: its owners sign a "Safe message" that
/// wraps the registry's digest, and their signatures, in increasing order of owner, are what
/// the Safe accepts.
contract SafeBaseSepoliaTest is Test {
    // Safe 1.4.1, read on Base Sepolia on 17 November 2026: code present, VERSION() "1.4.1".
    ISafeProxyFactory constant FACTORY = ISafeProxyFactory(0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67);
    address constant SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address constant FALLBACK_HANDLER = 0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;
    address constant SIGN_MESSAGE_LIB = 0xd53cd0aB83D845Ac265BE939c57F53AD838012c9;

    uint256 constant O1 = 0xD1;
    uint256 constant O2 = 0xD2;
    uint256 constant O3 = 0xD3;
    uint256 constant KEY = 0xA1;
    bytes32 constant WHY = keccak256("why");
    uint64 deadline;
    bool forked;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        forked = true;
        deadline = uint64(block.timestamp + 1 days);
    }

    /// A Safe owned by O1, O2 and O3, two of whom must sign.
    function _safe() internal returns (address safe) {
        address[] memory owners = new address[](3);
        (owners[0], owners[1], owners[2]) = (vm.addr(O1), vm.addr(O2), vm.addr(O3));
        bytes memory initializer = abi.encodeCall(
            ISafe.setup, (owners, 2, address(0), "", FALLBACK_HANDLER, address(0), 0, payable(address(0)))
        );
        safe = FACTORY.createProxyWithNonce(SINGLETON, initializer, uint256(keccak256("agent-only-tokens")));
        assertEq(ISafe(safe).getThreshold(), 2);
        assertEq(ISafe(safe).VERSION(), "1.4.1");
    }

    function _sign(uint256 pk, bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        return abi.encodePacked(r, s, v);
    }

    /// What the registry takes from the Safe: its address, and two owners' signatures of the
    /// Safe message that wraps `digest`.
    function _bySafe(address safe, uint256 pkA, uint256 pkB, bytes32 digest) internal view returns (bytes memory) {
        if (vm.addr(pkA) > vm.addr(pkB)) (pkA, pkB) = (pkB, pkA);
        bytes32 message = ISafeMessages(safe).getMessageHashForSafe(safe, abi.encode(digest));
        return abi.encode(safe, bytes.concat(_sign(pkA, message), _sign(pkB, message)));
    }

    function _ordered(address signerA, bytes memory a, address signerB, bytes memory b)
        internal
        pure
        returns (bytes[] memory sigs)
    {
        sigs = new bytes[](2);
        (sigs[0], sigs[1]) = signerA < signerB ? (a, b) : (b, a);
    }

    function test_ARealSafeAndAKeyApproveAVenue() public {
        vm.skip(!forked);
        address safe = _safe();
        address[] memory attesters = new address[](2);
        (attesters[0], attesters[1]) = (safe, vm.addr(KEY));
        AttestedAgentRegistry reg =
            new AttestedAgentRegistry(attesters, 2, 0.01 ether, 30 days, 0, IERC721(address(0)), address(0));
        address venue = address(new AgentSwap());
        bytes32 digest = reg.hashVenue(venue, true, WHY, deadline);
        bytes memory byKey = _sign(KEY, digest);

        // One owner is not the Safe.
        bytes32 message = ISafeMessages(safe).getMessageHashForSafe(safe, abi.encode(digest));
        bytes[] memory sigs = _ordered(safe, abi.encode(safe, _sign(O1, message)), vm.addr(KEY), byKey);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(venue, true, WHY, deadline, sigs);

        // Two owners who signed the registry's digest itself, not the Safe message.
        sigs = _ordered(safe, abi.encode(safe, bytes.concat(_sign(O2, digest), _sign(O1, digest))), vm.addr(KEY), byKey);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(venue, true, WHY, deadline, sigs);

        // Two owners who signed the removal of the venue.
        sigs = _ordered(safe, _bySafe(safe, O1, O2, reg.hashVenue(venue, false, WHY, deadline)), vm.addr(KEY), byKey);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(venue, true, WHY, deadline, sigs);

        sigs = _ordered(safe, _bySafe(safe, O1, O3, digest), vm.addr(KEY), byKey);
        reg.setVenue(venue, true, WHY, deadline, sigs);
        emit log_named_uint("venue approval by a real Safe (2 of 3) and a key, gas", vm.lastCallGas().gasTotalUsed);
        assertTrue(reg.isVenue(venue));
    }

    /// The Safe runs `data` at `to` in its own storage: a transaction of the Safe signed by O1 and O2.
    function _delegateFromSafe(address safe, address to, bytes memory data) internal {
        bytes32 txHash =
            ISafe(safe).getTransactionHash(to, 0, data, 1, 0, 0, 0, address(0), address(0), ISafe(safe).nonce());
        (uint256 pkA, uint256 pkB) = vm.addr(O1) < vm.addr(O2) ? (O1, O2) : (O2, O1);
        bytes memory owners = bytes.concat(_sign(pkA, txHash), _sign(pkB, txHash));
        ISafe(safe).execTransaction(to, 0, data, 1, 0, 0, 0, address(0), payable(address(0)), owners);
    }

    function _replaceEveryOwner(address safe) internal {
        for (uint256 i; i < 3; ++i) {
            address[] memory current = ISafe(safe).getOwners();
            vm.prank(safe);
            ISafe(safe).swapOwner(i == 0 ? address(1) : current[i - 1], current[i], vm.addr(0xE0 + i));
        }
        assertFalse(ISafe(safe).isOwner(vm.addr(O1)));
        assertFalse(ISafe(safe).isOwner(vm.addr(O2)));
        assertFalse(ISafe(safe).isOwner(vm.addr(O3)));
    }

    /// A Safe can approve a message on chain. The registry then takes the Safe named with an
    /// empty signature, which anyone can write, and that approval outlives the owners who gave
    /// it: what a Safe accepted this way is not taken back by changing its owners.
    function test_WhatASafeApprovedOnChainOutlivesItsOwners() public {
        vm.skip(!forked);
        address safe = _safe();
        address[] memory attesters = new address[](1);
        attesters[0] = safe;
        AttestedAgentRegistry reg =
            new AttestedAgentRegistry(attesters, 1, 0.01 ether, 30 days, 0, IERC721(address(0)), address(0));
        address venue = address(new AgentSwap());
        bytes32 digest = reg.hashVenue(venue, true, WHY, deadline);
        bytes[] memory unsigned = new bytes[](1);
        unsigned[0] = abi.encode(safe, "");
        bytes[] memory byOwners = new bytes[](1);
        byOwners[0] = _bySafe(safe, O1, O2, digest);

        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(venue, true, WHY, deadline, unsigned);

        // The Safe approves the message, through Safe's SignMessageLib.
        _delegateFromSafe(safe, SIGN_MESSAGE_LIB, abi.encodeCall(ISignMessageLib.signMessage, (abi.encode(digest))));
        assertEq(ISafe(safe).signedMessages(ISafeMessages(safe).getMessageHashForSafe(safe, abi.encode(digest))), 1);
        _replaceEveryOwner(safe);

        // What the former owners signed is refused; what the Safe approved on chain is accepted.
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(venue, true, WHY, deadline, byOwners);
        vm.prank(address(0xBAD));
        reg.setVenue(venue, true, WHY, deadline, unsigned);
        assertTrue(reg.isVenue(venue));
    }
}
