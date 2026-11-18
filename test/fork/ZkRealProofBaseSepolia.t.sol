// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IDcapAttestation} from "../../src/experimental/TdxQuoteVerifier.sol";
import {DstackConfigIdZkVerifier, IRiscZeroVerifier} from "../../src/experimental/DstackConfigIdZkVerifier.sol";

/// A real RISC Zero proof of our own dstack quote, checked by the real contracts of Base Sepolia
/// on a fork, with nothing simulated. Skipped unless BASE_SEPOLIA_RPC is set.
///
/// The proof (test/fork/zk/risc0-seal.hex) and the program's output (risc0-journal.hex) were made
/// on a rented Phala machine with Automata's DCAP v1.1 program; how is in test/fork/zk/README.md.
/// The fork's clock is set just after the time of the check written in the output, so that the
/// age limit, fixed at deployment, can be tested both ways.
contract ZkRealProofBaseSepoliaTest is Test {
    IDcapAttestation constant DCAP = IDcapAttestation(0xaDdeC7e85c2182202b66E331f2a4A0bBB2cEEa1F);
    IRiscZeroVerifier constant RISC0_ROUTER = IRiscZeroVerifier(0x0b144E07A0826182B6b59788c34b32Bfa86Fb711);
    bytes32 constant PROGRAM = 0xcc80dc6c1c1f8bc524101b72b3900301dc87887457c8fcaf552e45e2a02b9695;
    uint64 constant MAX_AGE = 1 hours;

    bool forked;
    bytes journal;
    bytes seal;
    uint64 checkedAt;
    DstackConfigIdZkVerifier verifier;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        forked = true;
        journal = vm.parseBytes(vm.readFile("test/fork/zk/risc0-journal.hex"));
        seal = vm.parseBytes(vm.readFile("test/fork/zk/risc0-seal.hex"));
        uint256 end = 2 + uint16(bytes2(_slice(journal, 0, 2)));
        bytes memory output = _slice(journal, 2, end - 2);
        checkedAt = uint64(bytes8(_slice(journal, end, 8)));
        vm.warp(checkedAt + 10 minutes);

        bytes32[] memory any = new bytes32[](1);
        any[0] = bytes32(uint256(1));
        bytes32[] memory approved = new bytes32[](1);
        approved[0] = _deploy(any).codeOf(output);
        verifier = _deploy(approved);
    }

    function _deploy(bytes32[] memory approved) internal returns (DstackConfigIdZkVerifier) {
        return new DstackConfigIdZkVerifier(DCAP, 1, approved, RISC0_ROUTER, PROGRAM, MAX_AGE);
    }

    function test_TheRealProofIsAcceptedByTheLiveVerifier() public {
        vm.skip(!forked);
        RISC0_ROUTER.verify(seal, PROGRAM, sha256(journal)); // reverts if the proof is not valid
    }

    function test_TheRealProofEnrollsOurCode() public {
        vm.skip(!forked);
        uint256 g = gasleft();
        bytes32 d = verifier.attestWithProof(journal, seal);
        g -= gasleft();
        console.log("attestWithProof with a real Groth16 proof, gas:", g);
        assertTrue(verifier.attested(d));
        assertLt(g, 1_000_000);
    }

    function test_AChangedProofIsRefused() public {
        vm.skip(!forked);
        bytes memory bad = seal;
        bad[40] ^= 0x01;
        vm.expectRevert();
        verifier.attestWithProof(journal, bad);
    }

    function test_AChangedOutputIsRefused() public {
        vm.skip(!forked);
        bytes memory bad = journal;
        bad[100] ^= 0x01;
        vm.expectRevert();
        verifier.attestWithProof(bad, seal);
    }

    function test_TheProofExpires() public {
        vm.skip(!forked);
        vm.warp(checkedAt + MAX_AGE + 1);
        vm.expectRevert(abi.encodeWithSelector(DstackConfigIdZkVerifier.StaleProof.selector, checkedAt));
        verifier.attestWithProof(journal, seal);
    }

    function _slice(bytes memory b, uint256 from, uint256 len) internal pure returns (bytes memory r) {
        r = new bytes(len);
        for (uint256 i; i < len; ++i) {
            r[i] = b[from + i];
        }
    }
}
