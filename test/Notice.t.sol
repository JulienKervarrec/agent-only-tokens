// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AgentSwap} from "../src/AgentSwap.sol";
import {AttestedAgentRegistry} from "../src/AttestedAgentRegistry.sol";
import {AgentOnlyBase} from "./AgentOnly.t.sol";

/// Stands in for a hardware verifier: it approves the digests it is told to.
contract StubVerifier {
    mapping(bytes32 => bool) public approved;

    function approve(bytes32 digest) external {
        approved[digest] = true;
    }

    function isValidSignature(bytes32 hash, bytes calldata) external view returns (bytes4) {
        return approved[hash] ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}

/// Attesters' decisions that widen what the registry accepts wait for the notice delay;
/// decisions that narrow it are immediate.
contract NoticeTest is AgentOnlyBase {
    bytes32 constant WHY = keccak256("review");
    address constant SPONSOR3 = address(0x103);

    function setUp() public override {
        super.setUp();
        vm.deal(SPONSOR3, 1 ether);
    }

    function _registry(uint64 delay, address verifier) internal returns (AttestedAgentRegistry) {
        address[] memory att = new address[](3);
        (att[0], att[1], att[2]) = (vm.addr(A1), vm.addr(A2), vm.addr(A3));
        return new AttestedAgentRegistry(att, 2, BOND, TTL, delay, IERC721(address(0)), verifier);
    }

    function _setVenue(address v, bool approved) internal {
        reg.setVenue(v, approved, WHY, FAR, _attest(A1, A2, reg.hashVenue(v, approved, WHY, FAR)));
    }

    function _announce(AttestedAgentRegistry r, address verifier) internal {
        r.setEnrollmentVerifier(verifier, WHY, FAR, _attest(A1, A2, r.hashVerifier(verifier, WHY, FAR)));
    }

    function _halt(AttestedAgentRegistry r) internal {
        r.haltEnrollments(WHY, FAR, _attest(A1, A2, r.hashHalt(WHY, FAR)));
    }

    /// An enrollment approved by `v` alone, with no attester signature.
    function _enrollBy(StubVerifier v, AttestedAgentRegistry r, uint256 agent, address key) internal {
        v.approve(r.hashEnrollment(agent, key, WHY, SPONSOR3, r.enrollmentNonce(agent), FAR));
        uint256 value = r.sponsorOf(agent) == address(0) ? BOND : 0;
        vm.prank(SPONSOR3);
        r.enroll{value: value}(agent, key, WHY, FAR, new bytes[](0));
    }

    // ------------------------------------------------------------ venues

    function test_VenueApprovalWaitsForTheNoticeDelay() public {
        AgentSwap late = new AgentSwap();
        uint256 id = _mint(K1, acc1);
        uint64 since = uint64(block.timestamp) + NOTICE;
        assertEq(reg.noticeDelay(), NOTICE);

        vm.expectEmit(address(reg));
        emit AttestedAgentRegistry.VenueSet(address(late), true, WHY, since);
        _setVenue(address(late), true);
        assertEq(reg.venueSince(address(late)), since);

        // Announced, not yet in force: the token treats it as any other stranger.
        assertFalse(reg.isVenue(address(late)));
        vm.prank(vm.addr(K1));
        _expectNotAgent(address(late));
        acc1.execute(address(nft), 0, abi.encodeCall(nft.approve, (address(late), id)));
        vm.warp(since - 1);
        assertFalse(reg.isVenue(address(late)));

        vm.warp(since);
        assertTrue(reg.isVenue(address(late)));
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(late), id)));
        _do(K1, acc1, address(late), abi.encodeCall(late.list, (nft, id, usdc, 1, address(0))));
        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(late), 1)));
        _do(K2, acc2, address(late), abi.encodeCall(late.buy, (nft, id, usdc, 1)));
        assertEq(nft.ownerOf(id), address(acc2));
    }

    function test_VenueRemovalIsImmediateAndCancelsAPendingApproval() public {
        // A venue in force is removed at once.
        vm.expectEmit(address(reg));
        emit AttestedAgentRegistry.VenueSet(address(swap), false, WHY, 0);
        _setVenue(address(swap), false);
        assertFalse(reg.isVenue(address(swap)));

        // An approval still waiting is cancelled: the date passes, nothing happens.
        address late = address(new AgentSwap());
        _setVenue(late, true);
        skip(NOTICE - 1);
        _setVenue(late, false);
        skip(NOTICE);
        assertFalse(reg.isVenue(late));
        assertEq(reg.venueSince(late), 0);
    }

    function test_ApprovingAVenueAgainDoesNotMoveItsDate() public {
        // In force: approving it again does not suspend it, and the event still gives its date.
        uint64 first = reg.venueSince(address(swap));
        vm.expectEmit(address(reg));
        emit AttestedAgentRegistry.VenueSet(address(swap), true, WHY, first);
        _setVenue(address(swap), true);
        assertTrue(reg.isVenue(address(swap)));

        // Waiting: approving it again does not postpone it.
        address late = address(new AgentSwap());
        _setVenue(late, true);
        uint64 since = reg.venueSince(late);
        skip(NOTICE / 2);
        _setVenue(late, true);
        assertEq(reg.venueSince(late), since);
        vm.warp(since);
        assertTrue(reg.isVenue(late));
    }

    function test_RemovedVenueWaitsAgainWhenApprovedAgain() public {
        _setVenue(address(swap), false);
        _setVenue(address(swap), true);
        assertFalse(reg.isVenue(address(swap)));
        skip(NOTICE);
        assertTrue(reg.isVenue(address(swap)));
    }

    function testFuzz_NoVenueBeforeItsDate(uint64 delay, uint64 wait) public {
        delay = uint64(bound(delay, 0, TTL - 1));
        wait = uint64(bound(wait, 0, 2 * TTL));
        AttestedAgentRegistry r = _registry(delay, address(0));
        address v = address(swap);
        r.setVenue(v, true, WHY, FAR, _attest(A1, A2, r.hashVenue(v, true, WHY, FAR)));
        skip(wait);
        assertEq(r.isVenue(v), wait >= delay);
    }

    // ------------------------------------------------------------ enrollment verifier

    function test_VerifierReplacementWaitsForTheNoticeDelay() public {
        AttestedAgentRegistry r = _registry(NOTICE, address(0));
        StubVerifier v = new StubVerifier();
        uint64 since = uint64(block.timestamp) + NOTICE;

        vm.expectEmit(address(r));
        emit AttestedAgentRegistry.EnrollmentVerifierSet(address(v), WHY, since);
        _announce(r, address(v));
        assertEq(r.announcedVerifier(), address(v));
        assertEq(r.announcedVerifierAt(), since);

        // Until the date, the rule in force stays: attesters sign, the new verifier counts for nothing.
        vm.warp(since - 1);
        assertEq(r.enrollmentVerifier(), address(0));
        _enroll(r, SPONSOR1, 1, vm.addr(K1), BOND);
        v.approve(r.hashEnrollment(2, vm.addr(K2), WHY, SPONSOR3, 0, FAR));
        vm.prank(SPONSOR3);
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        r.enroll{value: BOND}(2, vm.addr(K2), WHY, FAR, new bytes[](0));

        // From the date on, the new verifier decides alone.
        vm.warp(since);
        assertEq(r.enrollmentVerifier(), address(v));
        bytes32 d = r.hashAttestedEnrollment(1, vm.addr(K2), keccak256("evidence"), SPONSOR1, 1, FAR);
        bytes[] memory sigs = _attest(A1, A2, d);
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.NotVerified.selector);
        r.enroll(1, vm.addr(K2), keccak256("evidence"), FAR, sigs);
        _enrollBy(v, r, 2, vm.addr(K2));
        assertEq(r.keyOf(2), vm.addr(K2));
    }

    function test_ANewAnnouncementReplacesThePendingOne() public {
        AttestedAgentRegistry r = _registry(NOTICE, address(0));
        StubVerifier first = new StubVerifier();
        StubVerifier second = new StubVerifier();
        _announce(r, address(first));
        skip(NOTICE - 1);
        _announce(r, address(second));
        skip(NOTICE - 1); // well past the first date: the first verifier never took over
        assertEq(r.enrollmentVerifier(), address(0));
        skip(1);
        assertEq(r.enrollmentVerifier(), address(second));

        // Announcing the verifier in force cancels a pending replacement.
        _announce(r, address(first));
        _announce(r, address(second));
        skip(NOTICE);
        assertEq(r.enrollmentVerifier(), address(second));
    }

    /// A verifier that has taken over stays in force while its own replacement is waiting.
    function test_VerifierInForceStaysDuringTheNextNotice() public {
        AttestedAgentRegistry r = _registry(NOTICE, address(0));
        StubVerifier first = new StubVerifier();
        _announce(r, address(first));
        skip(NOTICE);
        _announce(r, address(new StubVerifier()));
        assertEq(r.enrollmentVerifier(), address(first));
        _enrollBy(first, r, 3, vm.addr(K1));
        assertEq(r.keyOf(3), vm.addr(K1));
    }

    function test_ZeroDelayDecisionsAreImmediate() public {
        AttestedAgentRegistry r = _registry(0, address(0));
        StubVerifier v = new StubVerifier();
        _announce(r, address(v));
        assertEq(r.enrollmentVerifier(), address(v));
        r.setVenue(address(swap), true, WHY, FAR, _attest(A1, A2, r.hashVenue(address(swap), true, WHY, FAR)));
        assertTrue(r.isVenue(address(swap)));
    }

    // ------------------------------------------------------------ halting enrollments

    function test_HaltStopsEnrollmentsAtOnce() public {
        uint256 id = _mint(K1, acc1);
        StubVerifier v = new StubVerifier();
        _announce(reg, address(v));
        assertFalse(reg.enrollmentHalted());

        vm.expectEmit(address(reg));
        emit AttestedAgentRegistry.EnrollmentsHalted(address(0), WHY);
        _halt(reg);
        assertTrue(reg.enrollmentHalted());

        // No new agent, and no new key for an existing one.
        bytes32 d = reg.hashAttestedEnrollment(3, vm.addr(K1), keccak256("evidence"), SPONSOR3, 0, FAR);
        bytes[] memory sigs = _attest(A1, A2, d);
        vm.prank(SPONSOR3);
        vm.expectRevert(AttestedAgentRegistry.Halted.selector);
        reg.enroll{value: BOND}(3, vm.addr(K1), keccak256("evidence"), FAR, sigs);
        d = reg.hashAttestedEnrollment(1, vm.addr(K2), keccak256("evidence"), SPONSOR1, 1, FAR);
        sigs = _attest(A1, A2, d);
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.Halted.selector);
        reg.enroll(1, vm.addr(K2), keccak256("evidence"), FAR, sigs);

        // Agents already enrolled keep acting with their current key.
        assertTrue(reg.isAgent(address(acc1)));
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(acc2), id)));

        // The announcement made before the halt is cancelled: its date passes, nothing resumes.
        assertEq(reg.announcedVerifier(), address(0));
        assertEq(reg.announcedVerifierAt(), 0);
        skip(NOTICE);
        assertTrue(reg.enrollmentHalted());
    }

    function test_HaltIsLiftedByAVerifierAnnouncedAfterwards() public {
        AttestedAgentRegistry r = _registry(NOTICE, address(0));
        StubVerifier v = new StubVerifier();
        _halt(r);
        _announce(r, address(v));
        skip(NOTICE - 1);
        assertTrue(r.enrollmentHalted());
        v.approve(r.hashEnrollment(3, vm.addr(K1), WHY, SPONSOR3, 0, FAR));
        vm.prank(SPONSOR3);
        vm.expectRevert(AttestedAgentRegistry.Halted.selector);
        r.enroll{value: BOND}(3, vm.addr(K1), WHY, FAR, new bytes[](0));

        skip(1);
        assertFalse(r.enrollmentHalted());
        _enrollBy(v, r, 3, vm.addr(K1));

        // Enrollments stay open while a later replacement is waiting.
        _announce(r, address(0));
        assertFalse(r.enrollmentHalted());
        _enrollBy(v, r, 3, vm.addr(K2));
        assertEq(r.keyOf(3), vm.addr(K2));
    }

    /// A verifier that took over by announcement is halted like any other, and the registry
    /// still shows which verifier was stopped.
    function test_HaltStopsAVerifierThatTookOverByAnnouncement() public {
        AttestedAgentRegistry r = _registry(NOTICE, address(0));
        StubVerifier v = new StubVerifier();
        _announce(r, address(v));
        skip(NOTICE);
        _enrollBy(v, r, 3, vm.addr(K1));

        vm.expectEmit(address(r));
        emit AttestedAgentRegistry.EnrollmentsHalted(address(v), WHY);
        _halt(r);
        assertTrue(r.enrollmentHalted());
        assertEq(r.enrollmentVerifier(), address(v));
        v.approve(r.hashEnrollment(3, vm.addr(K2), WHY, SPONSOR3, 1, FAR));
        vm.prank(SPONSOR3);
        vm.expectRevert(AttestedAgentRegistry.Halted.selector);
        r.enroll(3, vm.addr(K2), WHY, FAR, new bytes[](0));
        skip(NOTICE);
        assertTrue(r.enrollmentHalted());
    }

    /// Under a halt, any announcement lifts the halt when it takes over, even one that names
    /// the halted verifier. Only another halt cancels a pending announcement.
    function test_UnderAHaltOnlyAnotherHaltCancelsAnAnnouncement() public {
        StubVerifier broken = new StubVerifier();
        AttestedAgentRegistry r = _registry(NOTICE, address(broken));
        _halt(r);
        _announce(r, address(new StubVerifier()));
        skip(NOTICE - 1);
        _halt(r);
        skip(NOTICE);
        assertTrue(r.enrollmentHalted());
        assertEq(r.announcedVerifier(), address(0));
        assertEq(r.announcedVerifierAt(), 0);

        _announce(r, address(broken));
        skip(NOTICE);
        assertFalse(r.enrollmentHalted());
        assertEq(r.enrollmentVerifier(), address(broken));
    }

    // ------------------------------------------------------------ what a decision commits to

    /// The notice is there for the code to be read: an address that holds none is refused,
    /// or any code could be put there once the notice has passed.
    function test_AVenueOrAVerifierWithoutCodeIsRefused() public {
        address empty = address(0xBEEF);
        bytes[] memory sigs = _attest(A1, A2, reg.hashVenue(empty, true, WHY, FAR));
        vm.expectRevert(AttestedAgentRegistry.BadInput.selector);
        reg.setVenue(empty, true, WHY, FAR, sigs);
        sigs = _attest(A1, A2, reg.hashVerifier(empty, WHY, FAR));
        vm.expectRevert(AttestedAgentRegistry.BadInput.selector);
        reg.setEnrollmentVerifier(empty, WHY, FAR, sigs);
        // "No verifier" is not an address without code: attesters sign enrollments again.
        _announce(reg, address(0));
    }

    function test_SignaturesOnTheVerifierExpire() public {
        uint64 soon = uint64(block.timestamp) + 1 hours;
        StubVerifier v = new StubVerifier();
        bytes[] memory replacement = _attest(A1, A2, reg.hashVerifier(address(v), WHY, soon));
        bytes[] memory halt = _attest(A1, A2, reg.hashHalt(WHY, soon));
        // A later deadline than the one signed is not accepted.
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setEnrollmentVerifier(address(v), WHY, soon + 1, replacement);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.haltEnrollments(WHY, soon + 1, halt);

        skip(1 hours + 1);
        vm.expectRevert(AttestedAgentRegistry.Expired.selector);
        reg.setEnrollmentVerifier(address(v), WHY, soon, replacement);
        vm.expectRevert(AttestedAgentRegistry.Expired.selector);
        reg.haltEnrollments(WHY, soon, halt);
        assertFalse(reg.enrollmentHalted());
        assertEq(reg.announcedVerifierAt(), 0);
    }

    /// Someone holding a replacement the attesters signed and never sent cannot use it to
    /// void a halt they have just signed: halts have their own counter.
    function test_AnUnusedReplacementSentFirstDoesNotVoidAHalt() public {
        address stale = address(new StubVerifier());
        bytes[] memory replacement = _attest(A1, A2, reg.hashVerifier(stale, WHY, FAR));
        bytes[] memory halt = _attest(A1, A2, reg.hashHalt(WHY, FAR));
        vm.prank(human);
        reg.setEnrollmentVerifier(stale, WHY, FAR, replacement);
        reg.haltEnrollments(WHY, FAR, halt);
        assertTrue(reg.enrollmentHalted());
        skip(NOTICE);
        assertTrue(reg.enrollmentHalted()); // the stale replacement was cancelled by the halt
        assertEq(reg.haltNonce(), 1);
    }

    function test_OnlyTheAttestersHalt() public {
        bytes32 digest = reg.hashHalt(WHY, FAR);
        bytes[] memory one = new bytes[](1);
        one[0] = _sign(A1, digest);
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        reg.haltEnrollments(WHY, FAR, one);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.haltEnrollments(WHY, FAR, _attest(A1, HUMAN_PK, digest));
        bytes[] memory sigs = _attest(A1, A2, digest);
        // Signatures given for one reason do not serve another, nor another kind of decision.
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.haltEnrollments(keccak256("other"), FAR, sigs);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setEnrollmentVerifier(address(0), WHY, FAR, sigs);

        // A replacement signed before the halt and not yet used dies with it.
        address unsent = address(new StubVerifier());
        bytes[] memory unused = _attest(A1, A2, reg.hashVerifier(unsent, WHY, FAR));
        reg.haltEnrollments(WHY, FAR, sigs);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setEnrollmentVerifier(unsent, WHY, FAR, unused);
        // Once lifted, the old halt cannot be replayed by anyone.
        _announce(reg, address(0));
        skip(NOTICE);
        vm.prank(human);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.haltEnrollments(WHY, FAR, sigs);
        assertFalse(reg.enrollmentHalted());
    }
}
