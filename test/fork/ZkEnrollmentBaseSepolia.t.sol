// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IDcapAttestation, TdxQuoteVerifier} from "../../src/experimental/TdxQuoteVerifier.sol";
import {DstackConfigIdVerifier} from "../../src/experimental/DstackConfigIdVerifier.sol";
import {DstackConfigIdZkVerifier, IRiscZeroVerifier} from "../../src/experimental/DstackConfigIdZkVerifier.sol";

interface IPccsRouter {
    function getStandardTcbEvaluationDataNumberWithTimestamp(uint8 id, uint64 timestamp) external view returns (uint32);
    function getFmspcTcbContentHashWithTimestamp(uint8 id, bytes6 fmspc, uint32 version, uint32 tcbEval, uint64 t)
        external
        view
        returns (bytes32);
    function getQeIdentityContentHashWithTimestamp(uint8 id, uint256 pcsApiVersion, uint32 tcbEval, uint64 t)
        external
        view
        returns (bytes32);
    function getCertHashWithTimestamp(uint8 ca, uint64 t) external view returns (bytes32);
    function getCrlHashWithTimestamp(uint8 ca, uint64 t) external view returns (bytes32);
}

/// The zero-knowledge route of the dstack verifier against the real contracts of Base Sepolia,
/// on a fork. Skipped unless BASE_SEPOLIA_RPC is set.
///
/// No proof of our quote exists yet, so the RISC Zero check is simulated (`vm.mockCall`) for the
/// exact seal, program and output digest; everything after it is real: Automata's quote verifier
/// compares the Intel data hashes with those on chain, then our checks read the output. The
/// output is our own dstack quote's, as the direct route returns it, followed by the time of the
/// check and the hashes of the Intel data in force then, read on chain.
contract ZkEnrollmentBaseSepoliaTest is Test {
    IDcapAttestation constant DCAP = IDcapAttestation(0xaDdeC7e85c2182202b66E331f2a4A0bBB2cEEa1F);
    IRiscZeroVerifier constant RISC0_ROUTER = IRiscZeroVerifier(0x0b144E07A0826182B6b59788c34b32Bfa86Fb711);
    IPccsRouter constant PCCS = IPccsRouter(0xaf2a0D5473062b36E2dE986DA09d945EB26d492B);
    // Automata DCAP v1.1 RISC Zero guest program (releases/v1.1/NOTE.md of automata-dcap-attestation).
    bytes32 constant PROGRAM = 0xcc80dc6c1c1f8bc524101b72b3900301dc87887457c8fcaf552e45e2a02b9695;
    uint64 constant MAX_AGE = 1 hours;
    uint8 constant TDX = 1;
    uint8 constant TD_QE = 2;
    uint8 constant ROOT = 0;
    uint8 constant PLATFORM = 2;
    uint8 constant SIGNING = 3;

    bool forked;
    bytes output; // what the direct route returns for our quote
    bytes32 code;
    bytes32 digest;
    DstackConfigIdZkVerifier verifier;
    bytes seal = abi.encodePacked(bytes4(0x73c457ba), new bytes(256));

    function setUp() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        forked = true;
        bytes memory quote = vm.parseBytes(vm.readFile("test/experimental/phala/quote-own-prelaunch.hex"));
        vm.deal(address(this), 1 ether);
        bool ok;
        (ok, output) = DCAP.verifyAndAttestOnChain{value: 0.001 ether}(quote);
        assertTrue(ok);
        bytes32[] memory any = new bytes32[](1);
        any[0] = bytes32(uint256(1));
        code = _deploy(any).codeOf(output);
        bytes32[] memory approved = new bytes32[](1);
        approved[0] = code;
        verifier = _deploy(approved);
    }

    function _deploy(bytes32[] memory approved) internal returns (DstackConfigIdZkVerifier) {
        return new DstackConfigIdZkVerifier(DCAP, 1, approved, RISC0_ROUTER, PROGRAM, MAX_AGE);
    }

    /// The program's output: our output, the time of the check, and the Intel data hashes then.
    function _zkOutput(uint64 checkedAt) internal view returns (bytes memory) {
        bytes6 fmspc;
        bytes memory o = output;
        assembly {
            fmspc := mload(add(o, 37)) // output[5:11]
        }
        uint32 eval = PCCS.getStandardTcbEvaluationDataNumberWithTimestamp(TDX, checkedAt);
        return abi.encodePacked(
            uint16(output.length),
            output,
            checkedAt,
            PCCS.getFmspcTcbContentHashWithTimestamp(TDX, fmspc, 3, eval, checkedAt),
            PCCS.getQeIdentityContentHashWithTimestamp(TD_QE, 4, eval, checkedAt),
            PCCS.getCertHashWithTimestamp(ROOT, checkedAt),
            PCCS.getCertHashWithTimestamp(SIGNING, checkedAt),
            PCCS.getCrlHashWithTimestamp(ROOT, checkedAt),
            PCCS.getCrlHashWithTimestamp(PLATFORM, checkedAt)
        );
    }

    function _proofAccepted(bytes memory zk) internal {
        vm.mockCall(address(RISC0_ROUTER), abi.encodeCall(IRiscZeroVerifier.verify, (seal, PROGRAM, sha256(zk))), "");
    }

    function test_ProofRouteApprovesWhatTheDirectRouteWould() public {
        vm.skip(!forked);
        bytes memory zk = _zkOutput(uint64(block.timestamp));
        _proofAccepted(zk);
        uint256 g = gasleft();
        bytes32 d = verifier.attestWithProof(zk, seal);
        g -= gasleft();
        console.log("attestWithProof without the proof check, gas:", g);
        assertTrue(verifier.attested(d));
        assertEq(d, bytes32(abi.encodePacked(_slice(output, 11 + 520, 32))));
        assertLt(g, 600_000);
    }

    function test_AnInvalidProofIsRefused() public {
        vm.skip(!forked);
        bytes memory zk = _zkOutput(uint64(block.timestamp));
        vm.expectRevert(); // the real RISC Zero verifier refuses an empty seal
        verifier.attestWithProof(zk, seal);
    }

    function test_AProofForAnotherOutputIsRefused() public {
        vm.skip(!forked);
        bytes memory zk = _zkOutput(uint64(block.timestamp));
        _proofAccepted(zk);
        zk[100] ^= 0x01; // the proof no longer matches
        vm.expectRevert();
        verifier.attestWithProof(zk, seal);
    }

    function test_OldOrFutureChecksAreRefused() public {
        vm.skip(!forked);
        uint64 old = uint64(block.timestamp - MAX_AGE - 1);
        bytes memory zk = _zkOutput(old);
        _proofAccepted(zk);
        vm.expectRevert(abi.encodeWithSelector(DstackConfigIdZkVerifier.StaleProof.selector, old));
        verifier.attestWithProof(zk, seal);

        bytes memory recent = _zkOutput(uint64(block.timestamp - MAX_AGE));
        _proofAccepted(recent);
        verifier.attestWithProof(recent, seal);

        uint64 future = uint64(block.timestamp + 1);
        bytes memory early = abi.encodePacked(_slice(recent, 0, 2 + output.length), future, _slice(recent, 2 + output.length + 8, 192));
        _proofAccepted(early);
        vm.expectRevert(abi.encodeWithSelector(DstackConfigIdZkVerifier.StaleProof.selector, future));
        verifier.attestWithProof(early, seal);
    }

    function test_IntelDataOtherThanOnChainIsRefused() public {
        vm.skip(!forked);
        bytes memory zk = _zkOutput(uint64(block.timestamp));
        zk[2 + output.length + 8] ^= 0x01; // the platform data hash
        _proofAccepted(zk);
        vm.expectPartialRevert(TdxQuoteVerifier.QuoteRejected.selector);
        verifier.attestWithProof(zk, seal);
    }

    function test_UnapprovedCodeIsRefusedOnThisRouteToo() public {
        vm.skip(!forked);
        bytes32[] memory other = new bytes32[](1);
        other[0] = keccak256("another program");
        DstackConfigIdZkVerifier strict = _deploy(other);
        bytes memory zk = _zkOutput(uint64(block.timestamp));
        _proofAccepted(zk);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.UnknownCode.selector, code));
        strict.attestWithProof(zk, seal);
    }

    function test_MalformedOutputIsRefused() public {
        vm.skip(!forked);
        bytes memory zk = abi.encodePacked(_zkOutput(uint64(block.timestamp)), bytes1(0));
        _proofAccepted(zk);
        vm.expectRevert(DstackConfigIdZkVerifier.BadZkOutput.selector);
        verifier.attestWithProof(zk, seal);
    }

    function test_DirectRouteStillWorks() public {
        vm.skip(!forked);
        bytes memory quote = vm.parseBytes(vm.readFile("test/experimental/phala/quote-own-prelaunch.hex"));
        bytes32 d = verifier.attest{value: 0.001 ether}(quote);
        assertTrue(verifier.attested(d));
    }

    function test_RefusesEmptyConfiguration() public {
        vm.skip(!forked);
        bytes32[] memory approved = new bytes32[](1);
        approved[0] = code;
        vm.expectRevert(TdxQuoteVerifier.BadConfig.selector);
        new DstackConfigIdZkVerifier(DCAP, 1, approved, IRiscZeroVerifier(address(0)), PROGRAM, MAX_AGE);
        vm.expectRevert(TdxQuoteVerifier.BadConfig.selector);
        new DstackConfigIdZkVerifier(DCAP, 1, approved, RISC0_ROUTER, bytes32(0), MAX_AGE);
        vm.expectRevert(TdxQuoteVerifier.BadConfig.selector);
        new DstackConfigIdZkVerifier(DCAP, 1, approved, RISC0_ROUTER, PROGRAM, 0);
    }

    function _slice(bytes memory b, uint256 from, uint256 len) internal pure returns (bytes memory r) {
        r = new bytes(len);
        for (uint256 i; i < len; ++i) {
            r[i] = b[from + i];
        }
    }

    receive() external payable {}
}
