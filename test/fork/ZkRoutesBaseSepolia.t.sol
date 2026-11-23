// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

interface ISp1Verifier {
    function verifyProof(bytes32 programVKey, bytes calldata publicValues, bytes calldata proofBytes) external view;
}

interface ISp1Gateway is ISp1Verifier {
    function routes(bytes4 selector) external view returns (address verifier, bool frozen);
}

interface IRiscZeroRouter {
    function getVerifier(bytes4 selector) external view returns (address);
}

interface IZkEntrypoint {
    function programIdentifier(uint8 zkCoProcessor) external view returns (bytes32);
    function zkVerifier(uint8 zkCoProcessor) external view returns (address);
}

interface IEmergencyStop {
    function paused() external view returns (bool);
}

/// Phase 2 feasibility: what a zero-knowledge enrollment could rely on, on Base Sepolia.
/// Skipped unless BASE_SEPOLIA_RPC is set (see test/fork/zk/README.md for the proof's origin).
contract ZkRoutesBaseSepoliaTest is Test {
    ISp1Gateway constant SP1_GATEWAY = ISp1Gateway(0x397A5f7f3dBd538f23DE225B51f532c34448dA9B);
    ISp1Verifier constant SP1_V3 = ISp1Verifier(0xE780809121774D06aD9B0EEeC620fF4B3913Ced1);
    IRiscZeroRouter constant RISC0_ROUTER = IRiscZeroRouter(0x0b144E07A0826182B6b59788c34b32Bfa86Fb711);
    IZkEntrypoint constant AUTOMATA = IZkEntrypoint(0xaDdeC7e85c2182202b66E331f2a4A0bBB2cEEa1F);
    bytes32 constant PROGRAM = 0x0043e4e0c286cf4a2c03472ca2384f35a008558bc5de4e0f39d1d1bc989badca;
    bool forked;
    bytes publicValues;
    bytes proof;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        forked = true;
        publicValues = vm.parseBytes(string.concat("0x", vm.readFile("test/fork/zk/sp1-v3-public-values.hex")));
        proof = vm.parseBytes(string.concat("0x", vm.readFile("test/fork/zk/sp1-v3-proof.hex")));
    }

    /// A real proof that a TDX quote was checked is accepted on Base Sepolia for about 220,000 gas,
    /// and refused once its output is changed by one bit.
    function test_ARealProofOfAQuoteCheckIsCheapToVerify() public {
        vm.skip(!forked);
        uint256 g = gasleft();
        SP1_V3.verifyProof(PROGRAM, publicValues, proof);
        g -= gasleft();
        assertLt(g, 300_000);
        publicValues[publicValues.length - 1] ^= 0x01;
        vm.expectRevert();
        SP1_V3.verifyProof(PROGRAM, publicValues, proof);
    }

    /// That version is frozen: the gateway, the address an integrator should call, refuses it.
    function test_TheVulnerableVersionIsFrozen() public {
        vm.skip(!forked);
        (address verifier, bool frozen) = SP1_GATEWAY.routes(bytes4(proof));
        assertEq(verifier, address(SP1_V3));
        assertTrue(frozen);
        vm.expectRevert();
        SP1_GATEWAY.verifyProof(PROGRAM, publicValues, proof);
    }

    /// RISC Zero's router knows the Groth16 verifier Automata's proofs use; Automata's entrypoint on
    /// Base Sepolia has no zk program configured, so a zk enrollment would need its own contract.
    function test_RoutesAvailableToday() public {
        vm.skip(!forked);
        assertGt(RISC0_ROUTER.getVerifier(0x73c457ba).code.length, 0);
        for (uint8 kind = 1; kind <= 2; ++kind) {
            assertEq(AUTOMATA.programIdentifier(kind), bytes32(0));
            assertEq(AUTOMATA.zkVerifier(kind), address(0));
        }
    }

    /// Since 19 November 2026 the verifier Automata's proofs went through (3.0.0) is stopped for
    /// good, and a corrected one (3.1.0, selector 0xe71e6620) is routed: the zk route of this
    /// repository needs a new proof, made with the corrected prover, and a program built for it.
    function test_TheCorrectedVerifierIsRoutedAndTheOldOneStopped() public {
        vm.skip(!forked);
        assertTrue(IEmergencyStop(RISC0_ROUTER.getVerifier(0x73c457ba)).paused());
        assertFalse(IEmergencyStop(RISC0_ROUTER.getVerifier(0xe71e6620)).paused());
    }
}
