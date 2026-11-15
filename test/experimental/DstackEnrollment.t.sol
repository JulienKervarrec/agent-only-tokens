// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {AgentAccount} from "../../src/AgentAccount.sol";
import {AttestedAgentRegistry} from "../../src/AttestedAgentRegistry.sol";
import {TdxQuoteVerifier} from "../../src/experimental/TdxQuoteVerifier.sol";
import {DstackEnrollmentVerifier} from "../../src/experimental/DstackEnrollmentVerifier.sol";
import {Sha384} from "../../src/experimental/Sha384.sol";
import {Sha384Reference} from "./Sha384Reference.sol";
import {AgentOnlyBase} from "../AgentOnly.t.sol";
import {DcapStub} from "./TdxEnrollment.t.sol";

contract Sha384Harness {
    function hash(bytes memory data) external pure returns (bytes memory) {
        (bytes32 high, bytes16 low) = Sha384.hash(data);
        return abi.encodePacked(high, low);
    }

    function plain(bytes memory data) external pure returns (bytes memory) {
        (bytes32 high, bytes16 low) = Sha384Reference.hash(data);
        return abi.encodePacked(high, low);
    }
}

/// SHA-384 against reference values computed with Python's hashlib, on lengths around the
/// 128-byte block and the 112-byte padding limit. Input byte i is (7 * i + 3) mod 256.
contract Sha384Test is Test {
    Sha384Harness h = new Sha384Harness();

    function _input(uint256 n) internal pure returns (bytes memory data) {
        data = new bytes(n);
        for (uint256 i; i < n; ++i) {
            data[i] = bytes1(uint8((i * 7 + 3) % 256));
        }
    }

    function test_ReferenceVectors() public view {
        uint16[13] memory lengths = [0, 1, 3, 55, 56, 111, 112, 113, 127, 128, 129, 200, 300];
        bytes[13] memory expected = [
            bytes(hex"38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b"),
            hex"8a6c69af6fb6247635f837958446fb8f10e39bd5fbc244f7e635176339a3be614f6394247f01dbe1126c178c7bd48cb5",
            hex"de5060203c58b419f136c17666d339a05705575827e3600f0475f6fb3089870aede26c5a0903dea5938bcded4ee9e619",
            hex"fc2728f452750d08b5dbad1aea53202e7fc19c06894d13e36c433b0444a899277c49f16e0577c03db0f0605578836ef6",
            hex"6c969a865f38d2eaac60b7963a84c97ba27bcb76e589cbe1e2e89ead6aee4ad0337a4268f054be49c604ddd99692036d",
            hex"341388a9dc2275074e90cf394323761919761c805fd9e370977c9966a0e8c81a52135f02577670b0071638a4a26dbc31",
            hex"619cc5d06138526d70659eccf602d197e63e1050e22039a7feb40a30a5b2b08fb03729e291df12f8c576e6f1cd8af22a",
            hex"484a92d02b61b620ccae687fce4cd073eb995294a777d5deb5356bc8c1e2ce984f63f16420058ac5da666fda410a4feb",
            hex"f8234ab81f5f9641c656680825a9bbb3c2616bcc80b65d5e479a4d96742e1b8742330c9e8256ef5f03caa932487044ca",
            hex"e8480e9c4dd90f88104a79cbaccec48edbd798a142b4f241d726dc252f1502350e824c7d18dadd59d7d716919fb8f9bf",
            hex"430173387764874661acba1e914e50f6d0fbac534809e859b1da4396fad3d5f24c25c6a2d02486d8fbda3994713d981a",
            hex"8deb83535fa35d2f493c6c3695b1057b19232d2f531a0d398d2b958413855aa1594b6bcca0ddcbd24a981330a7ff1cc1",
            hex"060eb8e1c01cc6c6c8c03fcb7898155f2b836fb97c9d331a7a296a1a209aac9d261b2b268c4ba3c7299a3dd12b5bf81f"
        ];
        for (uint256 i; i < lengths.length; ++i) {
            assertEq(h.hash(_input(lengths[i])), expected[i]);
            assertEq(h.plain(_input(lengths[i])), expected[i]);
        }
    }

    /// The assembly version and the plain-Solidity version agree on random inputs.
    function testFuzz_AssemblyMatchesPlainSolidity(bytes memory data) public view {
        assertEq(h.hash(data), h.plain(data));
    }
}

/// Enrollment of an agent running on dstack. The fixtures are a real dstack quote and its real
/// RTMR3 event log (test/experimental/dstack), from dstack's own test suite. As in TdxEnrollment.t.sol, a
/// stand-in replaces the DCAP verifier and checks no signature.
contract DstackEnrollmentTest is AgentOnlyBase {
    uint256 constant BODY = 48; // report body offset in the quote
    uint256 constant TD_ATTRIBUTES = BODY + 120;
    uint256 constant MR_TD = BODY + 136;
    uint256 constant RTMR3 = BODY + 472;
    uint256 constant REPORT_DATA = BODY + 520;
    uint256 constant COMPOSE_INDEX = 2;
    bytes32 constant COMPOSE_HASH = 0x3763bc34552cf3a27ff71ad5f7a90471562a1a2df552dfc1998cba2d60da27e7;
    // keccak256(abi.encode(keccak256(report body bytes 120 to 472), COMPOSE_HASH)), computed outside Solidity.
    bytes32 constant REAL_CODE = 0x32fa81fbe81c6d1453821aad9889e0e23ae151e5b33b57238ae4365bfa832aac;
    bytes constant BOOT_DONE_V1 =
        hex"98bd7e6bd3952720b65027fd494834045d06b4a714bf737a06b874638b3ea00ff402f7f583e3e3b05e921c8570433ac6";
    uint256 constant ENCLAVE_KEY = 0x6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d;

    DcapStub dcap;
    DstackEnrollmentVerifier verifier;
    AttestedAgentRegistry dreg;
    bytes realQuote;
    bytes realEvents;

    function setUp() public override {
        super.setUp();
        realQuote = vm.parseBytes(vm.readFile("test/experimental/dstack/quote.hex"));
        realEvents = vm.parseBytes(vm.readFile("test/experimental/dstack/rtmr3-events.hex"));
        dcap = new DcapStub();
        verifier = new DstackEnrollmentVerifier(dcap, 1, _one(REAL_CODE));
        address[] memory att = new address[](3);
        (att[0], att[1], att[2]) = (vm.addr(A1), vm.addr(A2), vm.addr(A3));
        dreg = new AttestedAgentRegistry(att, 2, BOND, TTL, IERC721(address(0)), address(verifier));
    }

    // ------------------------------------------------------------ helpers

    function _one(bytes32 code) internal pure returns (bytes32[] memory list) {
        list = new bytes32[](1);
        list[0] = code;
    }

    function _write(bytes memory target, uint256 at, bytes memory data) internal pure {
        for (uint256 i; i < data.length; ++i) {
            target[at + i] = data[i];
        }
    }

    function _quoteFor(bytes32 digest) internal view returns (bytes memory quote) {
        quote = realQuote;
        _write(quote, REPORT_DATA, abi.encodePacked(digest, bytes32(0)));
    }

    /// The real quote, with RTMR3 set to the replay of `events` (what a machine that logged
    /// those events would report).
    function _quoteWithEvents(bytes memory events) internal view returns (bytes memory quote) {
        quote = realQuote;
        (bytes32 high, bytes16 low) = verifier.replay(events);
        _write(quote, RTMR3, abi.encodePacked(high, low));
    }

    function _event(bytes memory events, uint256 i) internal pure returns (bytes memory e) {
        e = new bytes(48);
        for (uint256 j; j < 48; ++j) {
            e[j] = events[i * 48 + j];
        }
    }

    function _setEvent(bytes memory events, uint256 i, bytes memory e) internal pure {
        _write(events, i * 48, e);
    }

    // ------------------------------------------------------------ the real fixture

    function test_RealEventLogReplaysToTheRealRtmr3() public view {
        (bytes32 high, bytes16 low) = verifier.replay(realEvents);
        bytes memory rtmr3 = new bytes(48);
        for (uint256 i; i < 48; ++i) {
            rtmr3[i] = realQuote[RTMR3 + i];
        }
        assertEq(abi.encodePacked(high, low), rtmr3);
        assertEq(realEvents.length, 8 * 48);
    }

    function test_ComposeEventDigestMatchesDstack() public view {
        // V1: the digest dstack logged for this event.
        (bytes32 high, bytes16 low) = verifier.composeEventDigest(COMPOSE_HASH, false);
        assertEq(abi.encodePacked(high, low), _event(realEvents, COMPOSE_INDEX));
        // V2: SHA-384 of the canonical JSON, computed outside Solidity.
        (high, low) = verifier.composeEventDigest(COMPOSE_HASH, true);
        assertEq(
            abi.encodePacked(high, low),
            hex"a8343acda0c3183342954754fb0e1916e6485fcbdc87c2338c3f28f28f9bc7f9ac2cc69f0fd1a15876431fff8c92a69b"
        );
    }

    function test_RealQuoteIsAccepted() public {
        // Untouched: its report data is 0x1234 followed by zeros.
        bytes32 digest = verifier.attest(realQuote, realEvents, COMPOSE_INDEX, false, COMPOSE_HASH);
        assertEq(digest, bytes32(uint256(0x1234) << 240));
        assertTrue(verifier.attested(digest));
    }

    // ------------------------------------------------------------ enrollment

    function test_DstackAgentEnrolls() public {
        address key = vm.addr(ENCLAVE_KEY);
        bytes32 digest = dreg.hashEnrollment(9, key, bytes32(0), SPONSOR1, 0, FAR);
        vm.prank(human); // anyone can carry the quote
        verifier.attest(_quoteFor(digest), realEvents, COMPOSE_INDEX, false, COMPOSE_HASH);

        vm.prank(SPONSOR1);
        dreg.enroll{value: BOND}(9, key, bytes32(0), FAR, new bytes[](0));
        assertTrue(dreg.isAgent(dreg.accountOf(9)));
        assertEq(AgentAccount(payable(dreg.accountOf(9))).agentId(), 9);
    }

    function test_AnotherInstanceOfTheSameAppIsAccepted() public {
        // Another instance id changes the event and RTMR3, not the code.
        bytes memory events = realEvents;
        _setEvent(events, 3, abi.encodePacked(keccak256("other instance"), bytes16(0)));
        verifier.attest(_quoteWithEvents(events), events, COMPOSE_INDEX, false, COMPOSE_HASH);
    }

    function test_V2EventLogIsAccepted() public {
        bytes memory events = realEvents;
        (bytes32 high, bytes16 low) = verifier.composeEventDigest(COMPOSE_HASH, true);
        _setEvent(events, COMPOSE_INDEX, abi.encodePacked(high, low));
        verifier.attest(_quoteWithEvents(events), events, COMPOSE_INDEX, true, COMPOSE_HASH);
    }

    // ------------------------------------------------------------ what is refused

    function test_RefusesOtherApplication() public {
        bytes32 other = keccak256("other compose file");
        bytes memory events = realEvents;
        (bytes32 high, bytes16 low) = verifier.composeEventDigest(other, false);
        _setEvent(events, COMPOSE_INDEX, abi.encodePacked(high, low));
        bytes memory q1 = _quoteWithEvents(events);
        vm.expectPartialRevert(TdxQuoteVerifier.UnknownCode.selector);
        verifier.attest(q1, events, COMPOSE_INDEX, false, other);
    }

    function test_RefusesOtherBaseImage() public {
        bytes memory quote = realQuote;
        quote[MR_TD] ^= 0x01;
        vm.expectPartialRevert(TdxQuoteVerifier.UnknownCode.selector);
        verifier.attest(quote, realEvents, COMPOSE_INDEX, false, COMPOSE_HASH);
    }

    function test_RefusesComposeHashTheLogDoesNotHold() public {
        // Claiming the approved compose hash while the log holds another one.
        bytes memory events = realEvents;
        (bytes32 high, bytes16 low) = verifier.composeEventDigest(keccak256("other"), false);
        _setEvent(events, COMPOSE_INDEX, abi.encodePacked(high, low));
        bytes memory q2 = _quoteWithEvents(events);
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(q2, events, COMPOSE_INDEX, false, COMPOSE_HASH);
        // Pointing at another event, or claiming the wrong format.
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(realQuote, realEvents, 1, false, COMPOSE_HASH);
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(realQuote, realEvents, COMPOSE_INDEX, true, COMPOSE_HASH);
    }

    function test_RefusesComposeEventWrittenByTheApplication() public {
        // The approved compose hash logged after boot-mr-done, as an application could do.
        bytes memory events = abi.encodePacked(_event(realEvents, 0), BOOT_DONE_V1, _event(realEvents, COMPOSE_INDEX));
        bytes memory q3 = _quoteWithEvents(events);
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(q3, events, 2, false, COMPOSE_HASH);
        // Same with the V2 form of boot-mr-done.
        bytes memory bootV2 =
            hex"aeadedb6d47c136395e76aaa640667ed1635429ee9a3795e0c97ad11f809b9805b39ba43d07f2e68cf51facd318d350d";
        events = abi.encodePacked(_event(realEvents, 0), bootV2, _event(realEvents, COMPOSE_INDEX));
        bytes memory q4 = _quoteWithEvents(events);
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(q4, events, 2, false, COMPOSE_HASH);
    }

    function test_RefusesEventLogThatDoesNotReplayToRtmr3() public {
        bytes memory events = realEvents;
        events[events.length - 1] ^= 0x01; // one bit of the last event
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(realQuote, events, COMPOSE_INDEX, false, COMPOSE_HASH);

        bytes memory shorter = new bytes(7 * 48); // last event dropped
        for (uint256 i; i < shorter.length; ++i) {
            shorter[i] = realEvents[i];
        }
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(realQuote, shorter, COMPOSE_INDEX, false, COMPOSE_HASH);
    }

    function test_RefusesMalformedEventLists() public {
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(realQuote, abi.encodePacked(realEvents, hex"00"), COMPOSE_INDEX, false, COMPOSE_HASH);
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(realQuote, realEvents, 8, false, COMPOSE_HASH);
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(realQuote, new bytes(65 * 48), COMPOSE_INDEX, false, COMPOSE_HASH);
    }

    function test_ComparesAll48BytesOfEachDigest() public {
        // An event whose first 32 bytes are those of the compose-hash event, and not the rest.
        bytes memory events = realEvents;
        events[COMPOSE_INDEX * 48 + 47] ^= 0x01;
        bytes memory quote = _quoteWithEvents(events);
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(quote, events, COMPOSE_INDEX, false, COMPOSE_HASH);

        // A quote whose RTMR3 differs from the replay in its last byte only.
        quote = realQuote;
        quote[RTMR3 + 47] ^= 0x01;
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(quote, realEvents, COMPOSE_INDEX, false, COMPOSE_HASH);
    }

    function test_RefusesMoreThan64Events() public {
        // A log of 65 events that is otherwise valid: the real one padded with app events.
        bytes memory events = realEvents;
        for (uint256 i = 8; i < 65; ++i) {
            events = abi.encodePacked(events, keccak256(abi.encode(i)), bytes16(0));
        }
        bytes memory quote = _quoteWithEvents(events);
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(quote, events, COMPOSE_INDEX, false, COMPOSE_HASH);
        // 64 events are accepted.
        bytes memory events64 = new bytes(64 * 48);
        for (uint256 i; i < events64.length; ++i) {
            events64[i] = events[i];
        }
        verifier.attest(_quoteWithEvents(events64), events64, COMPOSE_INDEX, false, COMPOSE_HASH);
    }

    /// Found by the independent review: a log without boot-mr-done after the compose hash
    /// cannot tell OS events from application events, so it is refused.
    function test_RefusesLogWithoutBootDoneAfterCompose() public {
        bytes memory events = abi.encodePacked(
            _event(realEvents, 0), _event(realEvents, 1), _event(realEvents, COMPOSE_INDEX), keccak256("app"), bytes16(0)
        );
        bytes memory quote = _quoteWithEvents(events);
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        verifier.attest(quote, events, COMPOSE_INDEX, false, COMPOSE_HASH);
    }

    function test_SharedChecksStillApply() public {
        bytes memory quote = realQuote;
        quote[TD_ATTRIBUTES] = 0x01;
        vm.expectRevert(TdxQuoteVerifier.DebugMachine.selector);
        verifier.attest(quote, realEvents, COMPOSE_INDEX, false, COMPOSE_HASH);

        dcap.set(true, 4, 2);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.PlatformNotAccepted.selector, uint8(4)));
        verifier.attest(realQuote, realEvents, COMPOSE_INDEX, false, COMPOSE_HASH);
    }

    function test_RefusesEmptyConfiguration() public {
        vm.expectRevert(TdxQuoteVerifier.BadConfig.selector);
        new DstackEnrollmentVerifier(dcap, 1, new bytes32[](0));
    }

    function test_GasOfAnAttestation() public {
        verifier.attest(realQuote, realEvents, COMPOSE_INDEX, false, COMPOSE_HASH);
        emit log_named_uint("attest, 8 events, stand-in DCAP verifier", vm.lastCallGas().gasTotalUsed);
    }
}
