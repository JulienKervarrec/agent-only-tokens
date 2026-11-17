// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {AgentSwap} from "../src/AgentSwap.sol";
import {AttestedAgentRegistry} from "../src/AttestedAgentRegistry.sol";
import {AgentOnlyBase} from "./AgentOnly.t.sol";
import {StubVerifier} from "./Notice.t.sol";

/// The attesters hand over to a new set of attesters. The handover is announced and the new
/// set decides only after the notice delay; until then the set in force keeps deciding.
contract AttestersTest is AgentOnlyBase {
    bytes32 constant WHY = keccak256("handover");
    uint256 constant B1 = 0xB1;
    uint256 constant B2 = 0xB2;
    uint256 constant B3 = 0xB3;
    uint256 constant B4 = 0xB4;
    uint256 constant B5 = 0xB5;
    uint256 constant C1 = 0xC1;
    address constant SPONSOR3 = address(0x103);

    function setUp() public override {
        super.setUp();
        vm.deal(SPONSOR3, 1 ether);
    }

    // ------------------------------------------------------------ helpers: a set is named by its keys

    function _set(uint256 a) internal pure returns (uint256[] memory pks) {
        pks = new uint256[](1);
        pks[0] = a;
    }

    function _set(uint256 a, uint256 b) internal pure returns (uint256[] memory pks) {
        pks = new uint256[](2);
        (pks[0], pks[1]) = (a, b);
    }

    function _set(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory pks) {
        pks = new uint256[](3);
        (pks[0], pks[1], pks[2]) = (a, b, c);
    }

    function _members(uint256[] memory pks) internal pure returns (address[] memory members) {
        members = new address[](pks.length);
        for (uint256 i; i < pks.length; ++i) {
            members[i] = vm.addr(pks[i]);
        }
    }

    /// Signatures of `digest` by the first `count` keys, in increasing order of address.
    function _signed(uint256[] memory pks, uint256 count, bytes32 digest) internal pure returns (bytes[] memory sigs) {
        uint256[] memory sorted = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            sorted[i] = pks[i];
        }
        for (uint256 i; i < count; ++i) {
            for (uint256 j = i + 1; j < count; ++j) {
                if (vm.addr(sorted[i]) > vm.addr(sorted[j])) (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
            }
        }
        sigs = new bytes[](count);
        for (uint256 i; i < count; ++i) {
            sigs[i] = _sign(sorted[i], digest);
        }
    }

    /// Two attesters of the set in force announce the next set, which accepts.
    function _handOver(AttestedAgentRegistry r, uint256 pkA, uint256 pkB, uint256[] memory next, uint256 needed)
        internal
    {
        address[] memory members = _members(next);
        bytes32 digest = r.hashAttesters(members, needed, WHY, FAR);
        r.setAttesters(members, needed, WHY, FAR, _attest(pkA, pkB, digest), _signed(next, needed, digest));
    }

    /// Signatures of two keys for the removal of `venue`: a decision that is immediate.
    function _removal(uint256 pkA, uint256 pkB, address venue) internal view returns (bytes[] memory) {
        return _attest(pkA, pkB, reg.hashVenue(venue, false, WHY, FAR));
    }

    function _fresh(uint64 delay) internal returns (AttestedAgentRegistry) {
        return
            new AttestedAgentRegistry(_members(_set(A1, A2, A3)), 2, BOND, TTL, delay, IERC721(address(0)), address(0));
    }

    // ------------------------------------------------------------ the notice

    function test_TheFirstSetIsNumberOneAndAnnouncedAtDeployment() public {
        address[] memory first = _members(_set(A1, A2, A3));
        vm.expectEmit();
        emit AttestedAgentRegistry.AttestersSet(1, first, 2, bytes32(0), uint64(block.timestamp));
        AttestedAgentRegistry r = _fresh(NOTICE);
        assertEq(r.attesterSet(), 1);
        assertEq(r.threshold(), 2);
        assertTrue(r.isAttester(vm.addr(A3)));
        assertTrue(r.isAttesterIn(1, vm.addr(A3)));
        assertFalse(r.isAttester(human));
        (uint256 set, uint256 needed, uint64 at) = r.announcedAttesters();
        assertEq(set + needed + at, 0);
    }

    function test_ANewSetDecidesOnlyAfterItsNotice() public {
        uint64 since = uint64(block.timestamp) + NOTICE;
        vm.expectEmit(address(reg));
        emit AttestedAgentRegistry.AttestersSet(2, _members(_set(B1, B2, B3)), 2, WHY, since);
        _handOver(reg, A1, A2, _set(B1, B2, B3), 2);
        (uint256 set, uint256 needed, uint64 at) = reg.announcedAttesters();
        assertEq(set, 2);
        assertEq(needed, 2);
        assertEq(at, since);
        assertTrue(reg.isAttesterIn(2, vm.addr(B1)));
        assertFalse(reg.isAttesterIn(2, vm.addr(A1)));

        // Until the date nothing changes: the set in force decides, the new one does not.
        skip(NOTICE - 1);
        assertEq(reg.attesterSet(), 1);
        assertTrue(reg.isAttester(vm.addr(A1)));
        assertFalse(reg.isAttester(vm.addr(B1)));
        bytes[] memory byNew = _removal(B1, B2, address(swap));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(address(swap), false, WHY, FAR, byNew);
        _enroll(reg, SPONSOR3, 3, address(0x3333), BOND);

        // At the date the new set decides, with no transaction, and the previous one no longer does.
        skip(1);
        assertEq(reg.attesterSet(), 2);
        assertFalse(reg.isAttester(vm.addr(A1)));
        assertTrue(reg.isAttester(vm.addr(B1)));
        bytes[] memory byOld = _removal(A1, A2, address(loan));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(address(loan), false, WHY, FAR, byOld);
        bytes[] memory rotation =
            _attest(A1, A2, reg.hashAttestedEnrollment(3, address(0x4444), keccak256("evidence"), SPONSOR3, 1, FAR));
        vm.prank(SPONSOR3);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.enroll(3, address(0x4444), keccak256("evidence"), FAR, rotation);
        // What the new set signed while the previous one was in force named that set: void too.
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(address(swap), false, WHY, FAR, byNew);
        reg.setVenue(address(swap), false, WHY, FAR, _removal(B1, B2, address(swap)));
        assertFalse(reg.isVenue(address(swap)));
    }

    function testFuzz_ASetTakesOverExactlyAtItsDate(uint64 delay, uint64 wait) public {
        delay = uint64(bound(delay, 0, TTL - 1));
        wait = uint64(bound(wait, 0, 2 * TTL));
        AttestedAgentRegistry r = _fresh(delay);
        _handOver(r, A1, A2, _set(B1, B2, B3), 2);
        skip(wait);
        assertEq(r.attesterSet(), wait >= delay ? 2 : 1);
        assertEq(r.isAttester(vm.addr(B2)), wait >= delay);
        assertEq(r.isAttester(vm.addr(A2)), wait < delay);
    }

    /// A registry deployed with no delay: a handover is immediate, and so is the next one.
    function test_WithNoDelayAHandoverIsImmediate() public {
        AttestedAgentRegistry r = _fresh(0);
        _handOver(r, A1, A2, _set(B1, B2, B3), 2);
        assertEq(r.attesterSet(), 2);
        assertTrue(r.isAttester(vm.addr(B1)));
        assertFalse(r.isAttester(vm.addr(A1)));
        _handOver(r, B1, B2, _set(C1), 1);
        assertEq(r.attesterSet(), 3);
        assertEq(r.threshold(), 1);
    }

    /// Venues approved and agents enrolled under a previous set are untouched by a handover,
    /// and so are a halt and a verifier still in its notice.
    function test_WhatEarlierSetsDecidedStays() public {
        AgentSwap late = new AgentSwap();
        reg.setVenue(address(late), true, WHY, FAR, _attest(A1, A2, reg.hashVenue(address(late), true, WHY, FAR)));
        reg.haltEnrollments(WHY, FAR, _attest(A1, A2, reg.hashHalt(WHY, FAR)));
        address verifier = address(new StubVerifier());
        reg.setEnrollmentVerifier(verifier, WHY, FAR, _attest(A1, A2, reg.hashVerifier(verifier, WHY, FAR)));
        uint64 verifierAt = reg.announcedVerifierAt();
        skip(1 days);

        _handOver(reg, A1, A2, _set(B1, B2, B3), 2); // accepted under a halt
        assertTrue(reg.enrollmentHalted());
        assertEq(reg.announcedVerifier(), verifier);
        assertEq(reg.announcedVerifierAt(), verifierAt);

        skip(NOTICE);
        assertEq(reg.attesterSet(), 2);
        assertTrue(reg.isVenue(address(swap)));
        assertTrue(reg.isVenue(address(late))); // announced by the previous set, in force on its own date
        assertTrue(reg.isAgent(address(acc1)));
        assertFalse(reg.enrollmentHalted()); // lifted by the verifier the previous set announced
        assertEq(reg.enrollmentVerifier(), verifier);
    }

    // ------------------------------------------------------------ several handovers

    /// A new announcement replaces the pending one: announcing the set in force cancels it.
    function test_AnnouncingAgainReplacesThePendingSet() public {
        _handOver(reg, A1, A2, _set(B1, B2, B3), 2);
        skip(NOTICE - 1);
        _handOver(reg, A1, A2, _set(A1, A2, A3), 2);
        (uint256 set,, uint64 at) = reg.announcedAttesters();
        assertEq(set, 3);
        assertEq(at, uint64(block.timestamp) + NOTICE);

        skip(1); // the date of the cancelled set passes
        assertEq(reg.attesterSet(), 1);
        assertFalse(reg.isAttester(vm.addr(B1)));
        skip(NOTICE);
        assertEq(reg.attesterSet(), 3);
        assertTrue(reg.isAttester(vm.addr(A3)));
        bytes[] memory byCancelled = _removal(B1, B2, address(swap));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(address(swap), false, WHY, FAR, byCancelled);
    }

    /// Each announcement gets a new number: the members of a cancelled set never leak into a later one.
    function test_SetNumbersAreNeverReused() public {
        _handOver(reg, A1, A2, _set(B1, B2, B3), 2); // set 2
        _handOver(reg, A1, A2, _set(C1, B4), 2); // set 3 replaces set 2
        _handOver(reg, A1, A2, _set(B1, B5), 1); // set 4 replaces set 3
        (uint256 set,,) = reg.announcedAttesters();
        assertEq(set, 4);
        assertEq(reg.attestersNonce(), 3);
        skip(NOTICE);
        assertEq(reg.attesterSet(), 4);
        assertTrue(reg.isAttester(vm.addr(B1)));
        assertTrue(reg.isAttester(vm.addr(B5)));
        assertFalse(reg.isAttester(vm.addr(B2)));
        assertFalse(reg.isAttester(vm.addr(B3)));
        assertFalse(reg.isAttester(vm.addr(C1)));
        assertFalse(reg.isAttester(vm.addr(B4)));
        assertFalse(reg.isAttester(vm.addr(A1)));
        assertTrue(reg.isAttesterIn(1, vm.addr(A1)));
        assertTrue(reg.isAttesterIn(2, vm.addr(B2)));
        assertTrue(reg.isAttesterIn(3, vm.addr(C1)));
    }

    /// A set that took over by announcement hands over in turn, and stays in force meanwhile,
    /// at its own threshold: three of three here.
    function test_ASetThatTookOverHandsOverInTurn() public {
        _handOver(reg, A1, A2, _set(B1, B2, B3), 3);
        skip(NOTICE);
        address[] memory last = _members(_set(C1));
        bytes32 digest = reg.hashAttesters(last, 1, WHY, FAR);
        bytes[] memory accepted = _signed(_set(C1), 1, digest);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // the first set is out
        reg.setAttesters(last, 1, WHY, FAR, _signed(_set(A1, A2, A3), 3, digest), accepted);
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector); // two of the three
        reg.setAttesters(last, 1, WHY, FAR, _attest(B1, B2, digest), accepted);
        reg.setAttesters(last, 1, WHY, FAR, _signed(_set(B1, B2, B3), 3, digest), accepted);

        skip(NOTICE - 1);
        assertEq(reg.attesterSet(), 2);
        assertEq(reg.threshold(), 3);
        assertTrue(reg.isAttester(vm.addr(B3)));
        digest = reg.hashVenue(address(swap), false, WHY, FAR);
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector); // still three of three
        reg.setVenue(address(swap), false, WHY, FAR, _attest(B2, B3, digest));
        reg.setVenue(address(swap), false, WHY, FAR, _signed(_set(B1, B2, B3), 3, digest));
        assertFalse(reg.isVenue(address(swap)));

        skip(1);
        assertEq(reg.attesterSet(), 3);
        assertEq(reg.threshold(), 1);
        assertFalse(reg.isAttester(vm.addr(B3)));
        digest = reg.hashVenue(address(loan), false, WHY, FAR);
        reg.setVenue(address(loan), false, WHY, FAR, _signed(_set(C1), 1, digest));
        assertFalse(reg.isVenue(address(loan)));
    }

    /// A set is not limited to three members: three of five here.
    function test_ASetOfFive() public {
        uint256[] memory five = new uint256[](5);
        (five[0], five[1], five[2], five[3], five[4]) = (B1, B2, B3, B4, B5);
        _handOver(reg, A1, A2, five, 3);
        skip(NOTICE);
        assertEq(reg.threshold(), 3);
        bytes32 digest = reg.hashVenue(address(swap), false, WHY, FAR);
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        reg.setVenue(address(swap), false, WHY, FAR, _attest(B4, B5, digest));
        reg.setVenue(address(swap), false, WHY, FAR, _signed(_set(B5, B3, B4), 3, digest));
        assertFalse(reg.isVenue(address(swap)));
    }

    // ------------------------------------------------------------ who hands over, and to what

    function test_OnlyTheSetInForceHandsOver() public {
        address[] memory next = _members(_set(B1, B2, B3));
        bytes32 digest = reg.hashAttesters(next, 2, WHY, FAR);
        bytes[] memory accepted = _attest(B1, B2, digest);
        bytes[] memory one = new bytes[](1);
        one[0] = _sign(A1, digest);
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        reg.setAttesters(next, 2, WHY, FAR, one, accepted);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setAttesters(next, 2, WHY, FAR, _attest(A1, HUMAN_PK, digest), accepted);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setAttesters(next, 2, WHY, FAR, accepted, accepted); // a set cannot appoint itself

        // The signatures cover the members, their order, the threshold, the reason and the deadline.
        bytes[] memory sigs = _attest(A1, A2, digest);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setAttesters(_members(_set(B1, B2, HUMAN_PK)), 2, WHY, FAR, sigs, accepted);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setAttesters(_members(_set(B2, B1, B3)), 2, WHY, FAR, sigs, accepted);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setAttesters(next, 1, WHY, FAR, sigs, accepted);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setAttesters(next, 2, keccak256("other"), FAR, sigs, accepted);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setAttesters(next, 2, WHY, FAR + 1, sigs, accepted);

        // Used once, they cannot be sent again, for example to undo a later handover.
        reg.setAttesters(next, 2, WHY, FAR, sigs, accepted);
        assertEq(reg.attestersNonce(), 1);
        vm.prank(human);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setAttesters(next, 2, WHY, FAR, sigs, accepted);
    }

    /// Enough members of the new set to reach its threshold sign the handover too. Without
    /// that, a registry could be handed by mistake to keys that nobody holds, for good.
    function test_TheNewSetMustAcceptItsAppointment() public {
        address[] memory next = _members(_set(B1, B2, B3));
        bytes32 digest = reg.hashAttesters(next, 2, WHY, FAR);
        bytes[] memory sigs = _attest(A1, A2, digest);
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        reg.setAttesters(next, 2, WHY, FAR, sigs, new bytes[](0));
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector); // one of the two needed
        reg.setAttesters(next, 2, WHY, FAR, sigs, _signed(_set(B3), 1, digest));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // the outgoing set cannot accept for it
        reg.setAttesters(next, 2, WHY, FAR, sigs, sigs);
        bytes[] memory other = _attest(B1, B2, reg.hashAttesters(next, 2, keccak256("other"), FAR));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // accepted something else
        reg.setAttesters(next, 2, WHY, FAR, sigs, other);

        // Two addresses that nobody holds: the set cannot reach its threshold, so it is refused.
        address[] memory lost = new address[](3);
        (lost[0], lost[1], lost[2]) = (vm.addr(B1), address(0xdead), address(swap));
        digest = reg.hashAttesters(lost, 2, WHY, FAR);
        sigs = _attest(A1, A2, digest);
        bytes[] memory alone = _signed(_set(B1), 1, digest);
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        reg.setAttesters(lost, 2, WHY, FAR, sigs, alone);
        // A refused handover leaves no trace.
        assertEq(reg.attestersNonce(), 0);
        assertFalse(reg.isAttesterIn(2, vm.addr(B1)));

        digest = reg.hashAttesters(next, 2, WHY, FAR);
        reg.setAttesters(next, 2, WHY, FAR, _attest(A1, A2, digest), _attest(B2, B3, digest));
        assertTrue(reg.isAttesterIn(2, vm.addr(B1)));
    }

    function test_ASetMustBeWellFormed() public {
        address[] memory next = _members(_set(B1, B2, B3));
        bytes32 digest = reg.hashAttesters(next, 0, WHY, FAR);
        vm.expectRevert(AttestedAgentRegistry.BadConfig.selector); // nobody needed
        reg.setAttesters(next, 0, WHY, FAR, _attest(A1, A2, digest), _attest(B1, B2, digest));
        digest = reg.hashAttesters(next, 4, WHY, FAR);
        vm.expectRevert(AttestedAgentRegistry.BadConfig.selector); // more signatures than members
        reg.setAttesters(next, 4, WHY, FAR, _attest(A1, A2, digest), _attest(B1, B2, digest));
        next[1] = address(0);
        digest = reg.hashAttesters(next, 2, WHY, FAR);
        vm.expectRevert(AttestedAgentRegistry.BadConfig.selector);
        reg.setAttesters(next, 2, WHY, FAR, _attest(A1, A2, digest), _attest(B1, B3, digest));
        next[1] = next[0]; // a member counted twice
        digest = reg.hashAttesters(next, 2, WHY, FAR);
        vm.expectRevert(AttestedAgentRegistry.BadConfig.selector);
        reg.setAttesters(next, 2, WHY, FAR, _attest(A1, A2, digest), _attest(B1, B3, digest));
        // A refused handover leaves no trace.
        assertEq(reg.attestersNonce(), 0);
        (uint256 set,, uint64 at) = reg.announcedAttesters();
        assertEq(set, 0);
        assertEq(at, 0);
    }

    // ------------------------------------------------------------ signatures given and never sent

    /// What attesters sign names their set. Once another set is in force, every signature given
    /// before and never sent is void, even from members who stay, and even if the same members
    /// are appointed again later.
    function test_AHandoverVoidsEverySignatureGivenBefore() public {
        bytes32 before = reg.hashVenue(address(loan), false, WHY, FAR);
        bytes[] memory removal = _attest(A1, A2, before);
        bytes[] memory alone = _signed(_set(A1), 1, before);
        bytes[] memory enrollment =
            _attest(A1, A2, reg.hashAttestedEnrollment(3, address(0x3333), WHY, SPONSOR3, 0, FAR));
        bytes[] memory revocation = _attest(A1, A2, reg.hashRevocation(2, FAR));
        bytes[] memory replacement = _attest(A1, A2, reg.hashVerifier(address(0), WHY, FAR));
        bytes[] memory halt = _attest(A1, A2, reg.hashHalt(WHY, FAR));

        // The two signers stay, and the threshold goes down to one.
        _handOver(reg, A1, A2, _set(A1, A2, B1), 1);
        skip(NOTICE);
        assertTrue(reg.hashVenue(address(loan), false, WHY, FAR) != before);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(address(loan), false, WHY, FAR, removal);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // one old signature is not a quorum
        reg.setVenue(address(loan), false, WHY, FAR, alone);
        vm.prank(SPONSOR3);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.enroll{value: BOND}(3, address(0x3333), WHY, FAR, enrollment);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.revoke(2, FAR, revocation);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setEnrollmentVerifier(address(0), WHY, FAR, replacement);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.haltEnrollments(WHY, FAR, halt);

        // The first set is appointed again: its old signatures stay void.
        _handOver(reg, A1, A2, _set(A1, A2, A3), 2);
        skip(NOTICE);
        assertEq(reg.attesterSet(), 3);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(address(loan), false, WHY, FAR, removal);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.haltEnrollments(WHY, FAR, halt);
        // Signed again under the set in force, the same decision passes.
        reg.setVenue(address(loan), false, WHY, FAR, _removal(A1, A2, address(loan)));
        assertFalse(reg.isVenue(address(loan)));
    }

    // ------------------------------------------------------------ every decision expires

    /// One signature set for each of the six decisions, all with the same deadline.
    struct Decisions {
        address[] next;
        bytes[] enrollment;
        bytes[] removal;
        bytes[] revocation;
        bytes[] handover;
        bytes[] accepted;
        bytes[] replacement;
        bytes[] halt;
    }

    function _decisions(uint64 deadline) internal view returns (Decisions memory d) {
        d.next = _members(_set(B1, B2, B3));
        bytes32 digest = reg.hashAttesters(d.next, 2, WHY, deadline);
        d.handover = _attest(A1, A2, digest);
        d.accepted = _attest(B1, B2, digest);
        d.enrollment = _attest(A1, A2, reg.hashAttestedEnrollment(3, address(0x3333), WHY, SPONSOR3, 0, deadline));
        d.removal = _attest(A1, A2, reg.hashVenue(address(swap), false, WHY, deadline));
        d.revocation = _attest(A1, A2, reg.hashRevocation(1, deadline));
        d.replacement = _attest(A1, A2, reg.hashVerifier(address(0), WHY, deadline));
        d.halt = _attest(A1, A2, reg.hashHalt(WHY, deadline));
    }

    function test_EveryDecisionIsAcceptedUntilItsLastSecondOnly() public {
        uint64 last = uint64(block.timestamp) + 1 hours;
        Decisions memory d = _decisions(last);
        // A later deadline than the one signed is not accepted.
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(address(swap), false, WHY, last + 1, d.removal);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.revoke(1, last + 1, d.revocation);

        skip(1 hours); // the last second: everything is still accepted
        uint256 before = vm.snapshotState();
        vm.prank(SPONSOR3);
        reg.enroll{value: BOND}(3, address(0x3333), WHY, last, d.enrollment);
        reg.setVenue(address(swap), false, WHY, last, d.removal);
        reg.revoke(1, last, d.revocation);
        reg.setAttesters(d.next, 2, WHY, last, d.handover, d.accepted);
        reg.setEnrollmentVerifier(address(0), WHY, last, d.replacement);
        reg.haltEnrollments(WHY, last, d.halt);
        assertFalse(reg.isVenue(address(swap)));
        assertFalse(reg.isAgent(address(acc1)));
        assertTrue(reg.enrollmentHalted());
        assertEq(reg.attestersNonce(), 1);

        vm.revertToState(before);
        skip(1); // one second later: nothing is
        vm.prank(SPONSOR3);
        vm.expectRevert(AttestedAgentRegistry.Expired.selector);
        reg.enroll{value: BOND}(3, address(0x3333), WHY, last, d.enrollment);
        vm.expectRevert(AttestedAgentRegistry.Expired.selector);
        reg.setVenue(address(swap), false, WHY, last, d.removal);
        vm.expectRevert(AttestedAgentRegistry.Expired.selector);
        reg.revoke(1, last, d.revocation);
        vm.expectRevert(AttestedAgentRegistry.Expired.selector);
        reg.setAttesters(d.next, 2, WHY, last, d.handover, d.accepted);
        vm.expectRevert(AttestedAgentRegistry.Expired.selector);
        reg.setEnrollmentVerifier(address(0), WHY, last, d.replacement);
        vm.expectRevert(AttestedAgentRegistry.Expired.selector);
        reg.haltEnrollments(WHY, last, d.halt);
        // A retired agent is still revocable until its bond is taken back, but not after the deadline.
        vm.prank(SPONSOR2);
        reg.retire(2);
        d.revocation = _attest(A1, A2, reg.hashRevocation(2, last));
        vm.expectRevert(AttestedAgentRegistry.Expired.selector);
        reg.revoke(2, last, d.revocation);
        assertTrue(reg.isVenue(address(swap)));
        assertTrue(reg.isAgent(address(acc1)));
        assertFalse(reg.enrollmentHalted());
        assertEq(reg.attestersNonce(), 0);
    }

    // ------------------------------------------------------------ what the attesters sign

    function _typed(bytes32 structHash) internal view returns (bytes32) {
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("AttestedAgentRegistry"),
                keccak256("1"),
                block.chainid,
                address(reg)
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }

    /// Each digest is the EIP-712 hash of its typed structure, recomputed here from the type
    /// written out in full: what a wallet shows the attester is what the registry checks.
    /// Everything the attesters sign ends with the number of their set, here the first.
    function test_WhatAttestersSignFollowsEip712() public view {
        address key = address(0x3333);
        assertEq(reg.attesterSet(), 1);
        assertEq(reg.venueNonce(address(swap)), 1);
        assertEq(
            reg.hashAttestedEnrollment(7, key, WHY, SPONSOR3, 5, FAR),
            _typed(
                keccak256(
                    abi.encode(
                        keccak256(
                            "AttestedEnrollment(uint256 agentId,address sessionKey,bytes32 evidenceHash,address sponsor,uint256 nonce,uint64 deadline,uint256 attesterSet)"
                        ),
                        7,
                        key,
                        WHY,
                        SPONSOR3,
                        5,
                        FAR,
                        1
                    )
                )
            )
        );
        assertEq(
            reg.hashVenue(address(swap), false, WHY, FAR),
            _typed(
                keccak256(
                    abi.encode(
                        keccak256(
                            "Venue(address venue,bool approved,bytes32 evidenceHash,uint256 nonce,uint64 deadline,uint256 attesterSet)"
                        ),
                        address(swap),
                        false,
                        WHY,
                        1,
                        FAR,
                        1
                    )
                )
            )
        );
        assertEq(
            reg.hashRevocation(7, FAR),
            _typed(
                keccak256(
                    abi.encode(keccak256("Revocation(uint256 agentId,uint64 deadline,uint256 attesterSet)"), 7, FAR, 1)
                )
            )
        );
        assertEq(
            reg.hashVerifier(address(swap), WHY, FAR),
            _typed(
                keccak256(
                    abi.encode(
                        keccak256(
                            "Verifier(address verifier,bytes32 evidenceHash,uint256 nonce,uint64 deadline,uint256 attesterSet)"
                        ),
                        address(swap),
                        WHY,
                        0,
                        FAR,
                        1
                    )
                )
            )
        );
        assertEq(
            reg.hashHalt(WHY, FAR),
            _typed(
                keccak256(
                    abi.encode(
                        keccak256("Halt(bytes32 evidenceHash,uint256 nonce,uint64 deadline,uint256 attesterSet)"),
                        WHY,
                        0,
                        FAR,
                        1
                    )
                )
            )
        );
        // An array is hashed as the concatenation of its members, each on 32 bytes.
        address[] memory next = _members(_set(B1, B2, B3));
        assertEq(
            reg.hashAttesters(next, 2, WHY, FAR),
            _typed(
                keccak256(
                    abi.encode(
                        keccak256(
                            "Attesters(address[] attesters,uint256 threshold,bytes32 evidenceHash,uint256 nonce,uint64 deadline,uint256 attesterSet)"
                        ),
                        keccak256(abi.encode(next[0], next[1], next[2])),
                        2,
                        WHY,
                        0,
                        FAR,
                        1
                    )
                )
            )
        );
    }

    /// What an enrollment verifier approves is the enrollment alone: it does not depend on who
    /// the attesters are, and programs that compute it need not know them.
    function test_WhatAVerifierApprovesDoesNotNameTheAttesters() public {
        address key = address(0x3333);
        bytes32 digest = reg.hashEnrollment(7, key, WHY, SPONSOR3, 5, FAR);
        assertEq(
            digest,
            _typed(
                keccak256(
                    abi.encode(
                        keccak256(
                            "Enrollment(uint256 agentId,address sessionKey,bytes32 evidenceHash,address sponsor,uint256 nonce,uint64 deadline)"
                        ),
                        7,
                        key,
                        WHY,
                        SPONSOR3,
                        5,
                        FAR
                    )
                )
            )
        );
        _handOver(reg, A1, A2, _set(B1, B2, B3), 2);
        skip(NOTICE);
        assertEq(reg.hashEnrollment(7, key, WHY, SPONSOR3, 5, FAR), digest);
        assertTrue(reg.hashAttestedEnrollment(7, key, WHY, SPONSOR3, 5, FAR) != digest);
    }
}
