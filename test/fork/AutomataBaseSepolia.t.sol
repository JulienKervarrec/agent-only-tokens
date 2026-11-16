// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IDcapAttestation, TdxQuoteVerifier} from "../../src/experimental/TdxQuoteVerifier.sol";
import {TdxEnrollmentVerifier} from "../../src/experimental/TdxEnrollmentVerifier.sol";

/// Our TDX verifier against the real Automata DCAP verifier deployed on Base Sepolia, on a fork.
/// Skipped unless BASE_SEPOLIA_RPC is set:
///   BASE_SEPOLIA_RPC=https://sepolia.base.org forge test --match-path 'test/fork/*'
/// Quote: test/experimental/tdx/quote-v4.hex, a real Intel TDX quote. Its report data is empty
/// and its platform level is "out of date" (4) on Automata's on-chain collateral.
contract AutomataBaseSepoliaTest is Test {
    // From automata-dcap-attestation, deployment/current/84532/dcap.json.
    IDcapAttestation constant DCAP = IDcapAttestation(0xaDdeC7e85c2182202b66E331f2a4A0bBB2cEEa1F);
    bytes32 constant REAL_CODE = 0x7dda0b4a87de3d2ad86eccd9d37cb9cc01bf17d97eb39abb2eabe2e8a1e81ce6;
    bytes quote;
    bool forked;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        forked = true;
        quote = vm.parseBytes(vm.readFile("test/experimental/tdx/quote-v4.hex"));
    }

    function _verifier(uint8 acceptedTcb) internal returns (TdxEnrollmentVerifier) {
        bytes32[] memory approved = new bytes32[](1);
        approved[0] = REAL_CODE;
        return new TdxEnrollmentVerifier(DCAP, acceptedTcb, approved);
    }

    function test_RealVerifierAcceptsTheQuoteAndOurChecksApply() public {
        vm.skip(!forked);
        address payer = makeAddr("payer");
        vm.deal(payer, 1 ether);

        // Only up-to-date platforms accepted: refused on the platform level, read from the real output.
        TdxEnrollmentVerifier strict = _verifier(1);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.PlatformNotAccepted.selector, uint8(4)));
        strict.attest(quote);

        // A deployment that also accepts "out of date": the genuine quote from approved code passes.
        TdxEnrollmentVerifier lax = _verifier(1 | (1 << 4));
        vm.prank(payer, payer); // payer is also tx.origin
        bytes32 digest = lax.attest{value: 0.001 ether}(quote);
        assertEq(digest, bytes32(0)); // the sample quote carries empty report data
        assertTrue(lax.attested(bytes32(0)));
        assertEq(payer.balance, 1 ether); // no fee kept on Base Sepolia; the value came back
        emit log_named_uint("attest through the real DCAP verifier, gas", vm.lastCallGas().gasTotalUsed);
    }

    function test_RealVerifierRejectsAnAlteredQuote() public {
        vm.skip(!forked);
        bytes memory altered = quote;
        altered[48 + 136] ^= 0x01; // one bit of the boot measurement: the signature no longer matches
        TdxEnrollmentVerifier lax = _verifier(1 | (1 << 4));
        // The P-256 precompile returns nothing for a bad signature, and Automata's verifier then
        // reverts instead of returning false. Either way the quote is rejected.
        vm.expectRevert();
        lax.attest(altered);
        assertFalse(lax.attested(bytes32(0)));
    }
}
