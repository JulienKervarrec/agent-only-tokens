// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AttestedAgentRegistry} from "../../src/AttestedAgentRegistry.sol";
import {DstackConfigIdZkVerifier, IRiscZeroVerifier} from "../../src/experimental/DstackConfigIdZkVerifier.sol";

/// The switch of step 2.3, on a fork of Base Sepolia: the registry of section 3.21 moves from
/// direct verification to the zk verifier through its replacement rule, announced by two
/// attesters on 18 November 2026. Skipped unless BASE_SEPOLIA_RPC is set.
///
/// The switch took effect on 19 November 2026 at 06:21 UTC. At 22:07:40 UTC the same day (block
/// 61020957) RISC Zero emergency-stopped the 3.0.0 verifier our zk verifier relies on, after a
/// soundness defect fixed in release 3.1.0: since then it can record no proof, so the registry could enroll or
/// renew no key. On 23 November 2026 two attesters announced the return to the direct verifier,
/// in force 24 hours later. The tests of the switch run on the chain as it was just before the
/// stop; the last three show the stop, that nobody else was enrolled meanwhile, and the return.
contract ZkSwitchBaseSepoliaTest is Test {
    AttestedAgentRegistry constant REG = AttestedAgentRegistry(payable(0xE78420EDf016b1249F2F8664ab172240C43BaD52));
    address constant OLD = 0x120D6d17c744900e94Ef59Fa6123Ac29e82D3A74;
    DstackConfigIdZkVerifier constant ZK =
        DstackConfigIdZkVerifier(payable(0x00679dc263Cc311905F3814C485795C2A0A19bF9));
    IRiscZeroVerifier constant RISC0 = IRiscZeroVerifier(0x0b144E07A0826182B6b59788c34b32Bfa86Fb711);
    address constant ACCOUNT = 0xD6eC25de098d6f23A8Bc180C1A95B8a1A5c238e7;
    uint64 constant TAKES_OVER = 1795065716;
    bytes32 constant CODE = 0xc58b0108a3e9d5c7797696433e408d555ba0fc9c8539ac1b4ac9dc5f4d73e924;
    bytes32 constant COMPOSE = 0x024261d8dbc43aef02147dc1790aae23d75e2bde92ddf899b294d3913f9e39b5;
    // The first enrollment of section 3.21, whose quote our real proof covers.
    address constant FIRST_KEY = 0x808EF3634f4DF8E607f931ef00b0069aF5Acf43A;
    uint64 constant FIRST_DEADLINE = 1794928632;
    uint256 constant BEFORE_STOP = 61_020_000; // 19 November 2026, about half an hour before the stop
    bytes4 constant STOPPED = 0xd93c0665; // EnforcedPause(), from RISC Zero's emergency stop
    uint64 constant RETURNS = 1795516169; // when the direct verifier is in force again

    string rpc;

    bool forked;
    address sponsor; // read from the registry: the sponsor of agent 1

    function setUp() public {
        rpc = vm.envOr("BASE_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc, BEFORE_STOP);
        forked = true;
        sponsor = REG.sponsorOf(1);
    }

    function test_TheZkVerifierIsAnnouncedAndApprovesTheSameCode() public {
        vm.skip(!forked);
        assertEq(REG.announcedVerifier(), address(ZK));
        assertEq(REG.announcedVerifierAt(), TAKES_OVER);
        assertTrue(ZK.isApprovedCode(CODE));
        assertEq(address(ZK.zkVerifier()), 0x0b144E07A0826182B6b59788c34b32Bfa86Fb711);
        assertEq(ZK.program(), 0xcc80dc6c1c1f8bc524101b72b3900301dc87887457c8fcaf552e45e2a02b9695);
        assertEq(ZK.maxAge(), 3 hours);
    }

    function test_DuringTheNoticeTheDirectVerifierStays() public {
        vm.skip(!forked);
        if (block.timestamp >= TAKES_OVER) return; // the notice is over on the live chain
        assertEq(REG.enrollmentVerifier(), OLD);
    }

    function test_AfterTheNoticeTheZkVerifierIsInForceAndTheAccountIsUnchanged() public {
        vm.skip(!forked);
        vm.warp(TAKES_OVER);
        assertEq(REG.enrollmentVerifier(), address(ZK));
        assertEq(REG.accountOf(1), ACCOUNT);
        assertTrue(REG.isAgent(ACCOUNT));
    }

    /// After the switch, an enrollment that only the old verifier approved is refused, and the
    /// same enrollment approved by the zk verifier goes through, on the same account.
    function test_AfterTheNoticeOnlyTheZkVerifierEnrolls() public {
        vm.skip(!forked);
        vm.warp(TAKES_OVER);
        address key = makeAddr("next session key");
        uint64 deadline = TAKES_OVER + 6 hours;
        bytes32 digest = REG.hashEnrollment(1, key, COMPOSE, sponsor, REG.enrollmentNonce(1), deadline);

        vm.store(OLD, keccak256(abi.encode(digest, uint256(0))), bytes32(uint256(1)));
        vm.prank(sponsor);
        vm.expectRevert(AttestedAgentRegistry.NotVerified.selector);
        REG.enroll(1, key, COMPOSE, deadline, new bytes[](0));

        vm.store(address(ZK), keccak256(abi.encode(digest, uint256(0))), bytes32(uint256(1)));
        assertTrue(ZK.attested(digest));
        vm.prank(sponsor);
        REG.enroll(1, key, COMPOSE, deadline, new bytes[](0));
        assertEq(REG.keyOf(1), key);
        assertEq(REG.accountOf(1), ACCOUNT);
    }

    /// The agent's second quote (nonce 2), proved on 18 November 2026 and recorded on chain by
    /// `attestWithProof`, renews its key after the notice, on the same account.
    function test_TheAgentsRecordedProofRenewsItsKeyAfterTheNotice() public {
        vm.skip(!forked);
        address key = 0xEb12d2F5c023e149646542C223510C5d899A31f8;
        uint64 deadline = 1795087316;
        bytes memory journal = vm.parseBytes(vm.readFile("test/fork/zk/switch-journal.hex"));
        bytes memory seal = vm.parseBytes(vm.readFile("test/fork/zk/switch-seal.hex"));
        bytes32 digest = REG.hashEnrollment(1, key, COMPOSE, sponsor, 2, deadline);
        RISC0.verify(seal, ZK.program(), sha256(journal)); // reverts if the proof is not valid
        assertTrue(ZK.attested(digest));
        if (REG.enrollmentNonce(1) != 2) return; // the renewal has happened on the live chain
        if (block.timestamp < TAKES_OVER) vm.warp(TAKES_OVER);
        vm.prank(sponsor);
        REG.enroll(1, key, COMPOSE, deadline, new bytes[](0));
        assertEq(REG.keyOf(1), key);
        assertEq(REG.accountOf(1), ACCOUNT);
        assertEq(REG.enrollmentNonce(1), 3);
    }

    /// The deployed zk verifier takes our real proof (at its time of check), and the digest it
    /// approves is that of the first enrollment of section 3.21: it cannot serve for the next one.
    function test_TheDeployedZkVerifierTakesOurRealProofForThatEnrollmentOnly() public {
        vm.skip(!forked);
        bytes memory journal = vm.parseBytes(vm.readFile("test/fork/zk/risc0-journal.hex"));
        bytes memory seal = vm.parseBytes(vm.readFile("test/fork/zk/risc0-seal.hex"));
        uint256 end = 2 + uint16(bytes2(abi.encodePacked(journal[0], journal[1])));
        uint64 checkedAt;
        for (uint256 i; i < 8; ++i) {
            checkedAt = (checkedAt << 8) | uint8(journal[end + i]);
        }
        vm.warp(checkedAt + 10 minutes);
        bytes32 digest = ZK.attestWithProof(journal, seal);
        assertTrue(ZK.attested(digest));
        assertEq(digest, REG.hashEnrollment(1, FIRST_KEY, COMPOSE, sponsor, 0, FIRST_DEADLINE));
        assertTrue(digest != REG.hashEnrollment(1, FIRST_KEY, COMPOSE, sponsor, REG.enrollmentNonce(1), FIRST_DEADLINE));
    }

    /// Today the zk verifier refuses the proof it took on 19 November: RISC Zero's verifier is stopped.
    function test_SinceTheEmergencyStopTheZkVerifierRecordsNoProof() public {
        vm.skip(!forked);
        vm.createSelectFork(rpc);
        bytes memory journal = vm.parseBytes(vm.readFile("test/fork/zk/switch-journal.hex"));
        bytes memory seal = vm.parseBytes(vm.readFile("test/fork/zk/switch-seal.hex"));
        vm.expectRevert(STOPPED);
        ZK.attestWithProof(journal, seal);
    }

    /// While the defective verifier was in force (about 16 hours), nobody else was enrolled: the
    /// registry holds one bond, and agent 1 still has the key and the nonce of our own renewal.
    function test_NobodyElseWasEnrolledThroughTheStoppedVerifier() public {
        vm.skip(!forked);
        vm.createSelectFork(rpc);
        assertEq(address(REG).balance, REG.bond());
        assertEq(REG.keyOf(1), 0xEb12d2F5c023e149646542C223510C5d899A31f8);
        assertEq(REG.enrollmentNonce(1), 3);
    }

    /// The return announced on 23 November 2026: the direct verifier is in force again after the
    /// notice, with the same account, and a key it approves can be enrolled.
    function test_TheDirectVerifierReturnsAfterTheNotice() public {
        vm.skip(!forked);
        vm.createSelectFork(rpc);
        if (block.timestamp < RETURNS) {
            assertEq(REG.announcedVerifier(), OLD);
            assertEq(REG.announcedVerifierAt(), RETURNS);
            vm.warp(RETURNS);
        }
        assertEq(REG.enrollmentVerifier(), OLD);
        assertEq(REG.accountOf(1), ACCOUNT);
        address key = makeAddr("key after the return");
        uint64 deadline = uint64(block.timestamp) + 1 hours;
        bytes32 digest = REG.hashEnrollment(1, key, COMPOSE, sponsor, REG.enrollmentNonce(1), deadline);
        vm.store(OLD, keccak256(abi.encode(digest, uint256(0))), bytes32(uint256(1)));
        vm.prank(sponsor);
        REG.enroll(1, key, COMPOSE, deadline, new bytes[](0));
        assertEq(REG.keyOf(1), key);
    }
}
