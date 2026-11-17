// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AttestedAgentRegistry} from "../src/AttestedAgentRegistry.sol";
import {AgentOnlyBase} from "./AgentOnly.t.sol";

/// A minimal multi-signature wallet for the tests: `needed` of its owners sign what it accepts.
/// What the owners sign names the wallet and the chain: one wallet's signatures are not another's.
contract TestWallet is IERC1271 {
    mapping(address => bool) public isOwner;
    uint256 public immutable needed;

    constructor(address[] memory owners, uint256 needed_) {
        for (uint256 i; i < owners.length; ++i) {
            isOwner[owners[i]] = true;
        }
        needed = needed_;
    }

    function hashFor(bytes32 hash) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), hash));
    }

    /// `signature`: the owners' 65-byte signatures of `hashFor(hash)`, in increasing order of owner.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (signature.length != needed * 65) return 0xffffffff;
        bytes32 signed = hashFor(hash);
        address last;
        for (uint256 i; i < needed; ++i) {
            (address owner,,) = ECDSA.tryRecover(signed, signature[i * 65:(i + 1) * 65]);
            if (!isOwner[owner] || owner <= last) return 0xffffffff;
            last = owner;
        }
        return IERC1271.isValidSignature.selector;
    }

    /// Unguarded: for the tests only.
    function setOwner(address owner, bool yes) external {
        isOwner[owner] = yes;
    }
}

/// Accepts every signature.
contract YesToAll is IERC1271 {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return IERC1271.isValidSignature.selector;
    }
}

/// A contract that answers badly: by reverting (0), with another value (1), with too few bytes (2),
/// or with the right value followed by something else in the same word (3). With 4 it answers well.
contract BadAnswer {
    uint256 public immutable mode;

    constructor(uint256 mode_) {
        mode = mode_;
    }

    fallback() external {
        if (mode == 0) revert("no");
        bytes32 word = bytes32(IERC1271.isValidSignature.selector);
        if (mode == 1) word = bytes32(uint256(1));
        if (mode == 3) word |= bytes32(uint256(0xff));
        uint256 size = mode == 2 ? 31 : 32;
        assembly {
            mstore(0, word)
            return(0, size)
        }
    }
}

/// A member that tries to change the registry while it is asked, and says yes only if that failed.
contract Reenterer {
    address public target;
    bytes public payload;

    function arm(address target_, bytes calldata payload_) external {
        (target, payload) = (target_, payload_);
    }

    function isValidSignature(bytes32, bytes calldata) external returns (bytes4) {
        (bool done,) = target.call(payload);
        return done ? bytes4(0) : IERC1271.isValidSignature.selector;
    }
}

/// Accepts one handover only: it recomputes the digest from the registry when it is asked.
contract OneHandover is IERC1271 {
    AttestedAgentRegistry public registry;
    address[] public members;
    uint256 public needed;
    bytes32 public why;
    uint64 public deadline;

    function expect(
        AttestedAgentRegistry registry_,
        address[] calldata members_,
        uint256 needed_,
        bytes32 why_,
        uint64 deadline_
    ) external {
        (registry, members, needed, why, deadline) = (registry_, members_, needed_, why_, deadline_);
    }

    function isValidSignature(bytes32 hash, bytes calldata) external view returns (bytes4) {
        bool same = hash == registry.hashAttesters(members, needed, why, deadline);
        return same ? IERC1271.isValidSignature.selector : bytes4(0);
    }
}

/// An attester can be a contract that signs by ERC-1271, for example a multi-signature wallet.
/// It is named with what it accepts: `abi.encode(member, signature)`. A key signs as before.
contract ContractAttestersTest is AgentOnlyBase {
    bytes32 constant WHY = keccak256("why");
    uint256 constant O1 = 0xD1;
    uint256 constant O2 = 0xD2;
    uint256 constant O3 = 0xD3;
    uint256 constant B1 = 0xB1;
    uint256 constant B2 = 0xB2;
    address constant SPONSOR3 = address(0x103);

    TestWallet wallet; // two of O1, O2, O3
    address venue; // any contract: a venue must hold code

    function setUp() public override {
        super.setUp();
        vm.deal(SPONSOR3, 1 ether);
        wallet = _wallet();
        venue = address(new YesToAll());
    }

    // ------------------------------------------------------------ helpers

    function _wallet() internal returns (TestWallet) {
        address[] memory owners = new address[](3);
        (owners[0], owners[1], owners[2]) = (vm.addr(O1), vm.addr(O2), vm.addr(O3));
        return new TestWallet(owners, 2);
    }

    /// What the registry takes from a member that is a contract.
    function _named(address member, bytes memory signature) internal pure returns (bytes memory) {
        return abi.encode(member, signature);
    }

    /// The wallet's signature of `digest`: two of its owners sign what the wallet asks them to.
    function _by(TestWallet w, uint256 pkA, uint256 pkB, bytes32 digest) internal view returns (bytes memory) {
        if (vm.addr(pkA) > vm.addr(pkB)) (pkA, pkB) = (pkB, pkA);
        bytes32 asked = w.hashFor(digest);
        return _named(address(w), bytes.concat(_sign(pkA, asked), _sign(pkB, asked)));
    }

    function _one(bytes memory a) internal pure returns (bytes[] memory sigs) {
        sigs = new bytes[](1);
        sigs[0] = a;
    }

    /// Two signatures, the one of the lower address first.
    function _two(address signerA, bytes memory a, address signerB, bytes memory b)
        internal
        pure
        returns (bytes[] memory sigs)
    {
        sigs = new bytes[](2);
        (sigs[0], sigs[1]) = signerA < signerB ? (a, b) : (b, a);
    }

    /// A registry with no notice delay, whose attesters are `memberA` and, if given, `memberB`.
    function _registry(address memberA, address memberB, uint256 needed) internal returns (AttestedAgentRegistry) {
        address[] memory members = new address[](memberB == address(0) ? 1 : 2);
        members[0] = memberA;
        if (memberB != address(0)) members[1] = memberB;
        return new AttestedAgentRegistry(members, needed, BOND, TTL, 0, IERC721(address(0)), address(0));
    }

    function _approval(AttestedAgentRegistry r) internal view returns (bytes32) {
        return r.hashVenue(venue, true, WHY, FAR);
    }

    function _approve(AttestedAgentRegistry r, bytes[] memory sigs) internal {
        r.setVenue(venue, true, WHY, FAR, sigs);
    }

    function _refused(AttestedAgentRegistry r, bytes[] memory sigs) internal {
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        r.setVenue(venue, true, WHY, FAR, sigs);
    }

    /// Refused by a revert that carries no data: what `abi.decode` does with bytes it cannot read.
    function _unreadable(AttestedAgentRegistry r, bytes[] memory sigs) internal {
        (bool done, bytes memory data) = address(r).call(abi.encodeCall(r.setVenue, (venue, true, WHY, FAR, sigs)));
        assertFalse(done);
        assertEq(data.length, 0);
    }

    /// A wallet whose address is below `above`, so that it can come first in a list.
    function _walletBelow(address above) internal returns (TestWallet w) {
        w = wallet;
        while (address(w) > above) w = _wallet();
    }

    // ------------------------------------------------------------ a wallet decides

    function test_AWalletAndAKeyApproveAVenue() public {
        AttestedAgentRegistry r = _registry(address(wallet), vm.addr(A1), 2);
        assertTrue(r.isAttester(address(wallet)));
        bytes32 digest = _approval(r);
        bytes memory byWallet = _by(wallet, O1, O3, digest);
        bytes memory byKey = _sign(A1, digest);

        // Neither is enough alone.
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        _approve(r, _one(byWallet));
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        _approve(r, _one(byKey));

        _approve(r, _two(address(wallet), byWallet, vm.addr(A1), byKey));
        assertTrue(r.isVenue(venue));
    }

    function test_AWalletAloneEnrollsAndRevokes() public {
        AttestedAgentRegistry r = _registry(address(wallet), address(0), 1);
        address key = vm.addr(K1);
        bytes[] memory sigs = _one(_by(wallet, O1, O2, r.hashAttestedEnrollment(7, key, WHY, SPONSOR3, 0, FAR)));
        vm.prank(SPONSOR3);
        r.enroll{value: BOND}(7, key, WHY, FAR, sigs);
        assertTrue(r.isAgent(r.accountOf(7)));

        r.revoke(7, FAR, _one(_by(wallet, O2, O3, r.hashRevocation(7, FAR))));
        assertFalse(r.isAgent(r.accountOf(7)));
    }

    function test_WhatTheWalletRefusesIsRefused() public {
        AttestedAgentRegistry r = _registry(address(wallet), address(0), 1);
        bytes32 digest = _approval(r);
        bytes32 asked = wallet.hashFor(digest);

        // One owner, where the wallet asks for two.
        _refused(r, _one(_named(address(wallet), _sign(O1, asked))));

        // The same owner twice.
        _refused(r, _one(_named(address(wallet), bytes.concat(_sign(O1, asked), _sign(O1, asked)))));

        // Two owners who signed another decision: the removal of the same venue.
        _refused(r, _one(_by(wallet, O1, O2, r.hashVenue(venue, false, WHY, FAR))));

        // Two owners who signed the registry's digest itself, not what the wallet asks them to sign.
        _refused(r, _one(_named(address(wallet), bytes.concat(_sign(O1, digest), _sign(O2, digest)))));

        // Another wallet with the same owners accepted it; this one did not.
        TestWallet twin = _wallet();
        bytes memory byTwin = _by(twin, O1, O2, digest);
        (, bytes memory signature) = abi.decode(byTwin, (address, bytes));
        _refused(r, _one(_named(address(wallet), signature)));

        // The twin is not a member.
        _refused(r, _one(byTwin));

        _approve(r, _one(_by(wallet, O1, O2, digest)));
        assertTrue(r.isVenue(venue));
    }

    function test_AWalletCountsOnce() public {
        AttestedAgentRegistry r = _registry(address(wallet), vm.addr(A1), 2);
        bytes32 digest = _approval(r);
        bytes[] memory sigs = new bytes[](2);
        // The same signature twice, then two different pairs of owners: one member either way.
        (sigs[0], sigs[1]) = (_by(wallet, O1, O2, digest), _by(wallet, O1, O2, digest));
        _refused(r, sigs);
        sigs[1] = _by(wallet, O2, O3, digest);
        _refused(r, sigs);
    }

    function test_AWalletDoesNotCountTwiceAroundAnotherMember() public {
        TestWallet w = _walletBelow(vm.addr(A1));
        address[] memory members = new address[](3);
        (members[0], members[1], members[2]) = (address(w), vm.addr(A1), vm.addr(A2));
        AttestedAgentRegistry r = new AttestedAgentRegistry(members, 3, BOND, TTL, 0, IERC721(address(0)), address(0));
        bytes32 digest = _approval(r);
        bytes[] memory sigs = new bytes[](3);
        (sigs[0], sigs[1], sigs[2]) = (_by(w, O1, O2, digest), _sign(A1, digest), _by(w, O2, O3, digest));
        _refused(r, sigs);
    }

    function test_AWalletComesInOrderLikeAKey() public {
        TestWallet w = _walletBelow(vm.addr(A1));
        AttestedAgentRegistry r = _registry(address(w), vm.addr(A1), 2);
        bytes32 digest = _approval(r);
        bytes[] memory sigs = new bytes[](2);
        (sigs[0], sigs[1]) = (_sign(A1, digest), _by(w, O1, O2, digest));
        _refused(r, sigs);
        (sigs[0], sigs[1]) = (sigs[1], sigs[0]);
        _approve(r, sigs);
    }

    function test_ABadElementAfterTheThresholdIsRefused() public {
        bytes32 digest = _approval(reg); // two of A1, A2, A3
        bytes[] memory two = _attest(A1, A2, digest);
        bytes[] memory sigs = new bytes[](3);
        (sigs[0], sigs[1]) = (two[0], two[1]);
        sigs[2] = new bytes(65);
        _refused(reg, sigs);
        sigs[2] = _sign(B1, digest); // a key that is not a member
        _refused(reg, sigs);
        sigs[2] = _named(address(wallet), ""); // a contract that is not a member
        _refused(reg, sigs);
        sigs[2] = two[0]; // a member again
        _refused(reg, sigs);
        _approve(reg, two);
    }

    /// The threshold counts addresses. A wallet and one of its owners are two addresses and the
    /// same people: here the two owners who sign for the wallet reach a threshold of two members.
    function test_TheThresholdCountsAddressesNotPeople() public {
        AttestedAgentRegistry r = _registry(address(wallet), vm.addr(O1), 2);
        bytes32 digest = _approval(r);
        _approve(r, _two(address(wallet), _by(wallet, O1, O2, digest), vm.addr(O1), _sign(O1, digest)));
        assertTrue(r.isVenue(venue));
    }

    function test_AWalletCanTakeBackWhatItAccepted() public {
        AttestedAgentRegistry r = _registry(address(wallet), address(0), 1);
        bytes[] memory sigs = _one(_by(wallet, O1, O2, _approval(r)));
        wallet.setOwner(vm.addr(O2), false);
        _refused(r, sigs);
        wallet.setOwner(vm.addr(O2), true);
        _approve(r, sigs);
        assertTrue(r.isVenue(venue));
    }

    // ------------------------------------------------------------ who is asked, and how

    function test_AContractThatIsNotAMemberIsNotAsked() public {
        YesToAll yes = new YesToAll();
        AttestedAgentRegistry r = _registry(address(wallet), address(0), 1);
        vm.expectCall(address(yes), abi.encodeWithSelector(IERC1271.isValidSignature.selector), 0);
        _refused(r, _one(_named(address(yes), "")));
    }

    function test_AContractThatIsAMemberIsAskedAboutTheDecisionItself() public {
        YesToAll yes = new YesToAll();
        AttestedAgentRegistry r = _registry(address(yes), address(0), 1);
        vm.expectCall(address(yes), abi.encodeCall(IERC1271.isValidSignature, (_approval(r), hex"1234")));
        _approve(r, _one(_named(address(yes), hex"1234")));
        assertTrue(r.isVenue(venue));
    }

    function test_AMemberAlreadyCountedIsNotAskedAgain() public {
        YesToAll yes = new YesToAll();
        AttestedAgentRegistry r = _registry(address(yes), vm.addr(A1), 2);
        bytes[] memory sigs = new bytes[](2);
        (sigs[0], sigs[1]) = (_named(address(yes), ""), _named(address(yes), hex"02"));
        vm.expectCall(address(yes), abi.encodeWithSelector(IERC1271.isValidSignature.selector), 1);
        _refused(r, sigs);
    }

    function test_AMemberCannotChangeTheRegistryWhileItIsAsked() public {
        Reenterer member = new Reenterer();
        AttestedAgentRegistry r = _registry(address(member), vm.addr(A1), 1);
        address other = address(new YesToAll());
        bytes memory approval =
            abi.encodeCall(r.setVenue, (other, true, WHY, FAR, _one(_sign(A1, r.hashVenue(other, true, WHY, FAR)))));
        member.arm(address(r), approval);

        _approve(r, _one(_named(address(member), ""))); // it said yes: what it tried had failed
        assertTrue(r.isVenue(venue));
        assertEq(r.venueNonce(other), 0);

        (bool done,) = address(r).call(approval); // sent directly, the same approval works
        assertTrue(done);
        assertTrue(r.isVenue(other));
    }

    function test_AKeyIsNotNamedAsAContract() public {
        // A1 is a member of the first registry and its signature is good, but a key signs in 65 bytes.
        bytes32 digest = _approval(reg);
        _refused(reg, _two(vm.addr(A1), _named(vm.addr(A1), _sign(A1, digest)), vm.addr(A2), _sign(A2, digest)));
        _approve(reg, _attest(A1, A2, digest));
    }

    function test_AWalletDoesNotSignAsAKey() public {
        // 65 bytes are read as a key's signature: the wallet's name is not in them.
        AttestedAgentRegistry r = _registry(address(wallet), address(0), 1);
        bytes32 digest = _approval(r);
        _refused(r, _one(_sign(O1, wallet.hashFor(digest))));
        _refused(r, _one(_sign(O1, digest)));
    }

    /// An account that a key controls can delegate to code (EIP-7702). It keeps signing by its
    /// key, and that code does not sign for it, even if it says yes to everything.
    /// forge-config: default.evm_version = "prague"
    function test_AnAccountThatDelegatesToCodeSignsByItsKeyOnly() public {
        address account = vm.addr(A1);
        bytes32 digest = _approval(reg);
        bytes[] memory named = _two(account, _named(account, ""), vm.addr(A2), _sign(A2, digest));
        _refused(reg, named);

        address code = address(new YesToAll());
        vm.signAndAttachDelegation(code, A1);
        (bool sent,) = address(0xdead).call(""); // any transaction carries the authorization
        assertTrue(sent);
        assertEq(account.code, abi.encodePacked(hex"ef0100", code));
        assertEq(IERC1271(account).isValidSignature(digest, ""), IERC1271.isValidSignature.selector);

        vm.expectCall(account, abi.encodeWithSelector(IERC1271.isValidSignature.selector), 0);
        _refused(reg, named);
        _approve(reg, _attest(A1, A2, digest));
        assertGt(reg.venueSince(venue), 0);
    }

    /// One address counts once, in whatever forms it signs. No real account signs both by a key
    /// and as a contract; code is placed at a key's address here to check the order rule alone.
    function test_OneAddressCountsOnceInWhateverFormItSigns() public {
        address both = vm.addr(A1);
        vm.etch(both, address(new YesToAll()).code);
        bytes32 digest = _approval(reg);
        bytes[] memory sigs = new bytes[](2);
        (sigs[0], sigs[1]) = (_sign(A1, digest), _named(both, ""));
        _refused(reg, sigs);
        (sigs[0], sigs[1]) = (_named(both, ""), _sign(A1, digest));
        _refused(reg, sigs);
        (sigs[0], sigs[1]) = (_named(both, ""), _named(both, hex"01"));
        _refused(reg, sigs);
    }

    function test_AMemberThatAnswersBadlyOnlyFails() public {
        for (uint256 mode; mode < 4; ++mode) {
            address bad = address(new BadAnswer(mode));
            _refused(_registry(bad, address(0), 1), _one(_named(bad, "")));
        }
        // The same contract with the right answer, in full: accepted.
        address good = address(new BadAnswer(4));
        AttestedAgentRegistry r = _registry(good, address(0), 1);
        _approve(r, _one(_named(good, "")));
        assertTrue(r.isVenue(venue));
    }

    function test_WhatCannotBeReadIsRefused() public {
        bytes32 digest = _approval(reg);
        bytes[] memory sigs = new bytes[](2);
        sigs[1] = _sign(A2, digest);

        // Neither 65 bytes nor an encoding of (address, bytes): a revert without data.
        sigs[0] = "";
        _unreadable(reg, sigs);
        sigs[0] = bytes.concat(_sign(A1, digest), hex"00");
        _unreadable(reg, sigs);
        // A member's address with something above its 160 bits.
        bytes memory dirty = _named(vm.addr(A1), "");
        dirty[0] = 0x01;
        sigs[0] = dirty;
        _unreadable(reg, sigs);

        // Zero bytes that do decode, to the zero address, and 65 zero bytes that recover nothing.
        sigs[0] = new bytes(64);
        _refused(reg, sigs);
        sigs[0] = new bytes(97);
        _refused(reg, sigs);
        sigs[0] = new bytes(65);
        _refused(reg, sigs);
    }

    function test_OtherFormsOfAKeysSignatureAreRefused() public {
        bytes32 digest = _approval(reg);
        bytes memory byA2 = _sign(A2, digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(A1, digest);

        // s replaced by n - s.
        _refused(reg, _two(vm.addr(A1), _highS(A1, digest), vm.addr(A2), byA2));
        // v written 0 or 1 instead of 27 or 28.
        _refused(reg, _two(vm.addr(A1), abi.encodePacked(r, s, v - 27), vm.addr(A2), byA2));
        // The "personal message" form of the same digest.
        bytes32 personal = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        _refused(reg, _two(vm.addr(A1), _sign(A1, personal), vm.addr(A2), byA2));
        // The compact form, 64 bytes: valid for the key, and not read as a key's signature.
        (bytes32 cr, bytes32 vs) = vm.signCompact(A1, digest);
        (address recovered,,) = ECDSA.tryRecover(digest, cr, vs);
        assertEq(recovered, vm.addr(A1));
        bytes[] memory sigs = _two(vm.addr(A1), abi.encodePacked(cr, vs), vm.addr(A2), byA2);
        (bool done,) = address(reg).call(abi.encodeCall(reg.setVenue, (venue, true, WHY, FAR, sigs)));
        assertFalse(done);

        _approve(reg, _two(vm.addr(A1), abi.encodePacked(r, s, v), vm.addr(A2), byA2));
    }

    /// The second valid signature of the same key for the same digest: s replaced by n - s.
    function _highS(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        s = bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - uint256(s));
        v = v == 27 ? 28 : 27;
        assertEq(ecrecover(digest, v, r, s), vm.addr(pk));
        return abi.encodePacked(r, s, v);
    }

    // ------------------------------------------------------------ handover to and from a wallet

    function test_AWalletTakesOverOnlyIfItAccepts() public {
        address[] memory next = new address[](1);
        next[0] = address(wallet);
        bytes32 digest = reg.hashAttesters(next, 1, WHY, FAR);
        bytes[] memory outgoing = _attest(A1, A2, digest);

        // The outgoing keys cannot accept in the wallet's place, and one owner is not the wallet.
        bytes[] memory accepted = _one(_sign(A1, digest));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setAttesters(next, 1, WHY, FAR, outgoing, accepted);
        accepted = _one(_named(address(wallet), _sign(O1, wallet.hashFor(digest))));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setAttesters(next, 1, WHY, FAR, outgoing, accepted);

        reg.setAttesters(next, 1, WHY, FAR, outgoing, _one(_by(wallet, O1, O2, digest)));

        // During the notice the wallet decides nothing, even beside a key of the set in force;
        // after it, the keys decide nothing.
        bytes32 halt = reg.hashHalt(WHY, FAR);
        bytes[] memory early = _two(address(wallet), _by(wallet, O1, O2, halt), vm.addr(A1), _sign(A1, halt));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.haltEnrollments(WHY, FAR, early);
        skip(NOTICE);
        assertTrue(reg.isAttester(address(wallet)));
        bytes[] memory byKeys = _attest(A1, A2, reg.hashHalt(WHY, FAR));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.haltEnrollments(WHY, FAR, byKeys);
        reg.haltEnrollments(WHY, FAR, _one(_by(wallet, O2, O3, reg.hashHalt(WHY, FAR))));
        assertTrue(reg.enrollmentHalted());
    }

    /// A key accepts by signing: someone holds it. A contract accepts by answering yes, here to
    /// an empty signature that anyone can write: nothing shows that someone controls it.
    function test_AContractAcceptsByAnsweringYes() public {
        address[] memory next = new address[](1);
        next[0] = address(new YesToAll());
        bytes32 digest = reg.hashAttesters(next, 1, WHY, FAR);
        reg.setAttesters(next, 1, WHY, FAR, _attest(A1, A2, digest), _one(_named(next[0], "")));
        skip(NOTICE);
        assertTrue(reg.isAttester(next[0]));
    }

    /// A contract that recomputes the digest from the registry when it is asked finds the one it
    /// is asked about, as a member of the set in force and as a member of the new set.
    function test_AContractAskedAboutAHandoverSeesItsDigest() public {
        OneHandover member = new OneHandover();
        AttestedAgentRegistry r = _registry(address(member), address(0), 1);
        address[] memory next = new address[](2);
        (next[0], next[1]) = (address(member), vm.addr(B1));
        bytes[] memory asked = _one(_named(address(member), ""));

        member.expect(r, next, 2, WHY, FAR); // another threshold than the one sent: refused
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        r.setAttesters(next, 1, WHY, FAR, asked, asked);

        member.expect(r, next, 1, WHY, FAR);
        r.setAttesters(next, 1, WHY, FAR, asked, asked);
        assertEq(r.attestersNonce(), 1);
        assertTrue(r.isAttester(vm.addr(B1)));
    }

    function test_AWalletHandsOverToKeys() public {
        AttestedAgentRegistry r = _registry(address(wallet), address(0), 1);
        address[] memory keys = new address[](2);
        (keys[0], keys[1]) = (vm.addr(B1), vm.addr(B2));
        bytes32 digest = r.hashAttesters(keys, 2, WHY, FAR);
        r.setAttesters(keys, 2, WHY, FAR, _one(_by(wallet, O1, O3, digest)), _attest(B1, B2, digest));
        assertFalse(r.isAttester(address(wallet)));
        assertTrue(r.isAttester(vm.addr(B1)));
        assertEq(r.threshold(), 2);
    }
}
