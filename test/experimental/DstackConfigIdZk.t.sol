// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TdxQuoteVerifier} from "../../src/experimental/TdxQuoteVerifier.sol";
import {DstackConfigIdVerifier} from "../../src/experimental/DstackConfigIdVerifier.sol";
import {
    DstackConfigIdZkVerifier,
    IRiscZeroVerifier,
    IDcapZkOutput
} from "../../src/experimental/DstackConfigIdZkVerifier.sol";
import {DcapStub} from "./TdxEnrollment.t.sol";

/// Stand-in for RISC Zero's verifier: accepts only the proofs registered with `accept`.
contract Risc0Stub is IRiscZeroVerifier {
    mapping(bytes32 => bool) public accepted;

    function accept(bytes calldata seal, bytes32 imageId, bytes32 journalDigest) external {
        accepted[keccak256(abi.encode(seal, imageId, journalDigest))] = true;
    }

    function verify(bytes calldata seal, bytes32 imageId, bytes32 journalDigest) external view {
        require(accepted[keccak256(abi.encode(seal, imageId, journalDigest))], "invalid proof");
    }
}

/// Stand-in for Automata's entrypoint and its version-4 quote verifier: hands back the output
/// inside a zk output, or refuses it as `genuineZk` says.
contract DcapZkStub is DcapStub, IDcapZkOutput {
    bool public genuineZk = true;

    function setZk(bool genuine_) external {
        genuineZk = genuine_;
    }

    function quoteVerifiers(uint16 version) external view returns (IDcapZkOutput) {
        return version == 4 ? IDcapZkOutput(address(this)) : IDcapZkOutput(address(0));
    }

    function verifyZkOutput(bytes calldata zk, uint32 tcbEvalNumber) external view returns (bool, bytes memory) {
        require(tcbEvalNumber == 0, "standard evaluation expected");
        if (!genuineZk) return (false, bytes("collateral hash mismatch"));
        return (true, zk[2:2 + uint16(bytes2(zk[0:2]))]);
    }
}

/// The zero-knowledge route of the dstack verifier, on our own quote of 17 November 2026
/// (test/experimental/phala/quote-own-prelaunch.hex), with stand-ins for the proof system and
/// for Automata. test/fork/ZkEnrollmentBaseSepolia.t.sol runs it against the real contracts.
contract DstackConfigIdZkTest is Test {
    uint256 constant BODY = 48; // the report body starts after the quote's header
    uint256 constant MR_CONFIG_ID = BODY + 184;
    uint256 constant REPORT_DATA = BODY + 520;
    bytes32 constant PROGRAM = keccak256("pinned program");
    uint64 constant MAX_AGE = 1 hours;
    uint64 constant NOW = 2_000_000_000;

    DcapZkStub dcap;
    Risc0Stub risc0;
    DstackConfigIdZkVerifier verifier;
    bytes quote;
    bytes32 code;
    bytes seal = hex"73c457ba01";

    function setUp() public {
        vm.warp(NOW);
        quote = vm.parseBytes(vm.readFile("test/experimental/phala/quote-own-prelaunch.hex"));
        dcap = new DcapZkStub();
        risc0 = new Risc0Stub();
        code = _codeOf(quote);
        verifier = _verifier(code);
    }

    function _verifier(bytes32 approved) internal returns (DstackConfigIdZkVerifier) {
        bytes32[] memory list = new bytes32[](1);
        list[0] = approved;
        return new DstackConfigIdZkVerifier(dcap, 1, list, risc0, PROGRAM, MAX_AGE);
    }

    function _codeOf(bytes memory q) internal pure returns (bytes32 h) {
        assembly ("memory-safe") {
            h := keccak256(add(add(q, 0x20), 168), 352)
        }
    }

    /// The program's output for a quote: version, body type, security level, platform family,
    /// report body, then the time of the check and six data hashes.
    function _zk(bytes memory q, uint16 version, uint8 tcbStatus, uint64 checkedAt) internal pure returns (bytes memory) {
        bytes memory body = new bytes(584);
        for (uint256 i; i < 584; ++i) {
            body[i] = q[BODY + i];
        }
        bytes memory output = abi.encodePacked(version, uint16(2), tcbStatus, bytes6(0), body);
        return abi.encodePacked(uint16(output.length), output, checkedAt, new bytes(192));
    }

    function _zk(bytes memory q) internal pure returns (bytes memory) {
        return _zk(q, 4, 0, NOW);
    }

    function _proven(bytes memory zk) internal returns (bytes memory) {
        risc0.accept(seal, PROGRAM, sha256(zk));
        return zk;
    }

    function _word(bytes memory b, uint256 at) internal pure returns (bytes32 w) {
        assembly ("memory-safe") {
            w := mload(add(add(b, 0x20), at))
        }
    }

    function test_ProvenOutputIsApprovedLikeTheQuote() public {
        bytes memory zk = _proven(_zk(quote));
        vm.expectEmit(address(verifier));
        emit TdxQuoteVerifier.Attested(_word(quote, REPORT_DATA), code, keccak256(zk));
        bytes32 digest = verifier.attestWithProof(zk, seal);
        assertEq(digest, _word(quote, REPORT_DATA));
        assertTrue(verifier.attested(digest));
        assertEq(verifier.isValidSignature(digest, ""), bytes4(0x1626ba7e));
    }

    function test_UnprovenOutputIsRefused() public {
        bytes memory zk = _zk(quote);
        vm.expectRevert("invalid proof");
        verifier.attestWithProof(zk, seal);
    }

    function test_ProofOfAnotherProgramIsRefused() public {
        bytes memory zk = _zk(quote);
        risc0.accept(seal, keccak256("another program"), sha256(zk));
        vm.expectRevert("invalid proof");
        verifier.attestWithProof(zk, seal);
    }

    function test_ProofCoversTheWholeOutput() public {
        bytes memory zk = _proven(_zk(quote));
        zk[zk.length - 1] = 0x01; // one of the data hashes
        vm.expectRevert("invalid proof");
        verifier.attestWithProof(zk, seal);
    }

    function test_MalformedOutputsAreRefused() public {
        bytes memory oneByte = _proven(hex"00");
        vm.expectRevert(DstackConfigIdZkVerifier.BadZkOutput.selector);
        verifier.attestWithProof(oneByte, seal);

        bytes memory tiny = _proven(hex"0001");
        vm.expectRevert(DstackConfigIdZkVerifier.BadZkOutput.selector);
        verifier.attestWithProof(tiny, seal);

        bytes memory longer = _proven(abi.encodePacked(_zk(quote), bytes1(0)));
        vm.expectRevert(DstackConfigIdZkVerifier.BadZkOutput.selector);
        verifier.attestWithProof(longer, seal);

        bytes memory full = _zk(quote);
        bytes memory shorter = new bytes(full.length - 1);
        for (uint256 i; i < shorter.length; ++i) {
            shorter[i] = full[i];
        }
        _proven(shorter);
        vm.expectRevert(DstackConfigIdZkVerifier.BadZkOutput.selector);
        verifier.attestWithProof(shorter, seal);
    }

    function test_CheckOlderThanMaxAgeIsRefused() public {
        bytes memory edge = _proven(_zk(quote, 4, 0, NOW - MAX_AGE));
        verifier.attestWithProof(edge, seal);

        bytes memory old = _proven(_zk(quote, 4, 0, NOW - MAX_AGE - 1));
        vm.expectRevert(abi.encodeWithSelector(DstackConfigIdZkVerifier.StaleProof.selector, NOW - MAX_AGE - 1));
        verifier.attestWithProof(old, seal);
    }

    function test_CheckDatedInTheFutureIsRefused() public {
        bytes memory future = _proven(_zk(quote, 4, 0, NOW + 1));
        vm.expectRevert(abi.encodeWithSelector(DstackConfigIdZkVerifier.StaleProof.selector, NOW + 1));
        verifier.attestWithProof(future, seal);
    }

    function test_UnknownQuoteVersionIsRefused() public {
        bytes memory v5 = _proven(_zk(quote, 5, 0, NOW));
        vm.expectRevert(TdxQuoteVerifier.UnsupportedReport.selector);
        verifier.attestWithProof(v5, seal);
    }

    function test_IntelDataRefusedByAutomataIsRefused() public {
        dcap.setZk(false);
        bytes memory zk = _proven(_zk(quote));
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.QuoteRejected.selector, bytes("collateral hash mismatch")));
        verifier.attestWithProof(zk, seal);
    }

    function test_SharedChecksApplyOnThisRoute() public {
        bytes memory outdated = _proven(_zk(quote, 4, 4, NOW));
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.PlatformNotAccepted.selector, 4));
        verifier.attestWithProof(outdated, seal);

        bytes memory q = bytes.concat(quote);
        q[BODY + 120] = 0x01; // debug flag
        bytes memory debug = _proven(_zk(q));
        vm.expectRevert(TdxQuoteVerifier.DebugMachine.selector);
        verifier.attestWithProof(debug, seal);

        q = bytes.concat(quote);
        q[REPORT_DATA + 63] = 0x01; // second half of the report data not empty
        bytes memory dirty = _proven(_zk(q));
        vm.expectRevert(TdxQuoteVerifier.BadReportData.selector);
        verifier.attestWithProof(dirty, seal);
    }

    function test_ApprovedCodeAndFormatApplyOnThisRoute() public {
        DstackConfigIdZkVerifier strict = _verifier(keccak256("another program"));
        bytes memory zk = _proven(_zk(quote));
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.UnknownCode.selector, code));
        strict.attestWithProof(zk, seal);

        bytes memory q = bytes.concat(quote);
        q[MR_CONFIG_ID] = 0x00; // unset MRCONFIGID format
        DstackConfigIdZkVerifier lax = _verifier(_codeOf(q));
        bytes memory unset = _proven(_zk(q));
        vm.expectRevert(DstackConfigIdVerifier.BadConfigId.selector);
        lax.attestWithProof(unset, seal);
    }

    function test_DirectRouteUnchanged() public {
        bytes32 digest = verifier.attest(quote);
        assertEq(digest, _word(quote, REPORT_DATA));
    }

    function test_RefusesIncompleteConfiguration() public {
        bytes32[] memory list = new bytes32[](1);
        list[0] = code;
        vm.expectRevert(TdxQuoteVerifier.BadConfig.selector);
        new DstackConfigIdZkVerifier(dcap, 1, list, IRiscZeroVerifier(address(0)), PROGRAM, MAX_AGE);
        vm.expectRevert(TdxQuoteVerifier.BadConfig.selector);
        new DstackConfigIdZkVerifier(dcap, 1, list, risc0, bytes32(0), MAX_AGE);
        vm.expectRevert(TdxQuoteVerifier.BadConfig.selector);
        new DstackConfigIdZkVerifier(dcap, 1, list, risc0, PROGRAM, 0);
    }
}
