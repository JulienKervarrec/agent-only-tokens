// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IDcapAttestation, TdxQuoteVerifier} from "../../src/experimental/TdxQuoteVerifier.sol";
import {DstackDocumentVerifier} from "../../src/experimental/DstackDocumentVerifier.sol";

/// The verifier for MRCONFIGID in format 3 against the real Automata DCAP verifier on Base
/// Sepolia, on a fork at the block where that machine's key was enrolled (23 November 2026), so
/// that Intel's data is the one of that day. Skipped unless BASE_SEPOLIA_RPC is set.
/// Quote: test/experimental/phala/os064-quote.hex, a machine with dstack OS 0.6.4.
contract DocumentBaseSepoliaTest is Test {
    IDcapAttestation constant DCAP = IDcapAttestation(0xaDdeC7e85c2182202b66E331f2a4A0bBB2cEEa1F);
    uint256 constant THAT_DAY = 62_578_716;
    bytes20 constant APP = hex"7304267bd32e1b49e6efa19ab73a756ee30c14e7";
    bytes20 constant INSTANCE = hex"b3416d34c3cc2fbb760d38767ce6094807161e5b";
    bytes32 constant COMPOSE = 0x66dfe96ab4493d8f81c21567f409b4bca40502907adf9f5472196d503a34b513;
    bytes constant KEY_PROVIDER =
        hex"3059301306072a8648ce3d020106082a8648ce3d03010703420004e8e325a477b0bf22800dc927a46c68638938d283fe73d1f9028eeac7028193f3470122193875f598b7addc503e534712ab437b4120776bbac32ddf8897f844ee";
    bytes32 constant DIGEST = 0xc76134bb92174ec024c80b421d70b56dac0393e9b4e66914dc1e1ac2fa1c81ce;
    bytes quote;
    bool forked;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc, THAT_DAY);
        forked = true;
        quote = vm.parseBytes(vm.readFile("test/experimental/phala/os064-quote.hex"));
    }

    function _verifier(bytes32 approved) internal returns (DstackDocumentVerifier) {
        bytes32[] memory list = new bytes32[](1);
        list[0] = approved;
        return new DstackDocumentVerifier(DCAP, 1, list); // up-to-date platforms only
    }

    function test_RealVerifierAcceptsTheQuoteAndTheProgramIsApproved() public {
        vm.skip(!forked);
        (bool ok, bytes memory output) = DCAP.verifyAndAttestOnChain(quote);
        assertTrue(ok);
        DstackDocumentVerifier probe = _verifier(bytes32(uint256(1)));
        bytes32 program = probe.programOf(probe.imageOf(output), COMPOSE, KEY_PROVIDER);
        DstackDocumentVerifier verifier = _verifier(program);
        assertEq(verifier.attest(quote, APP, INSTANCE, COMPOSE, KEY_PROVIDER), DIGEST);
        assertTrue(verifier.attested(DIGEST));
        // The approval that was made that day for this one machine covered the whole field;
        // this one names no machine.
        vm.expectRevert(DstackDocumentVerifier.BadConfigId.selector);
        verifier.attest(quote, APP, bytes20(uint160(INSTANCE) ^ 1), COMPOSE, KEY_PROVIDER);
    }

    function test_RealVerifierRejectsTheQuoteWithAnotherField() public {
        vm.skip(!forked);
        DstackDocumentVerifier verifier = _verifier(bytes32(uint256(1)));
        bytes memory altered = bytes.concat(quote);
        altered[48 + 184 + 1] ^= 0x01; // one bit of MRCONFIGID: the processor's signature no longer holds
        vm.expectRevert();
        verifier.attest(altered, APP, INSTANCE, COMPOSE, KEY_PROVIDER);
    }
}
