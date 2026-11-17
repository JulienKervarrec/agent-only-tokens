// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAgentRegistry} from "../../src/IAgentRegistry.sol";
import {AttestedAgentRegistry} from "../../src/AttestedAgentRegistry.sol";
import {AnyCollection} from "../AgentOnly.t.sol";

/// A registry whose answers the prover chooses freely.
contract FreeRegistry is IAgentRegistry {
    mapping(address => bool) public isAgent;
    mapping(address => bool) public isVenue;

    function set(address a, bool agent, bool venue) external {
        isAgent[a] = agent;
        isVenue[a] = venue;
    }
}

/// Properties proved with Halmos (symbolic execution): every argument of a `check_` function
/// stands for all possible values at once, so a passing check holds for every input, not only
/// for sampled ones. Run with `halmos --match-contract AgentOnlyProps`.
///
/// Setting: three accounts whose agent and venue status is arbitrary, a token held by the
/// first, and any one action by any of them.
contract AgentOnlyProps is Test {
    FreeRegistry reg;
    AnyCollection nft;
    address constant A = address(0xA11CE);
    address constant B = address(0xB0B);
    address constant C = address(0xC4A1);
    uint256 id;

    function _setUp(bool aAgent, bool aVenue, bool bAgent, bool bVenue, bool cAgent, bool cVenue) internal {
        reg = new FreeRegistry();
        nft = new AnyCollection(IAgentRegistry(address(reg)));
        reg.set(A, true, false);
        vm.prank(A);
        id = nft.mint(bytes32(0));
        // Statuses may change after the mint (an agent frozen, a venue removed...).
        reg.set(A, aAgent, aVenue);
        reg.set(B, bAgent, bVenue);
        reg.set(C, cAgent, cVenue);
    }

    function _allowed(address x) internal view returns (bool) {
        return reg.isAgent(x) || reg.isVenue(x);
    }

    function _pick(uint8 i) internal pure returns (address) {
        return i % 3 == 0 ? A : (i % 3 == 1 ? B : C);
    }

    /// One arbitrary action, by an arbitrary account, towards an arbitrary account.
    function _act(uint8 action, address caller, address target) internal returns (bool ok) {
        vm.prank(caller);
        if (action % 6 == 0) {
            (ok,) = address(nft).call(abi.encodeCall(IERC721.transferFrom, (A, target, id)));
        } else if (action % 6 == 1) {
            (ok,) =
                address(nft).call(abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", A, target, id));
        } else if (action % 6 == 2) {
            (ok,) = address(nft).call(abi.encodeCall(IERC721.approve, (target, id)));
        } else if (action % 6 == 3) {
            (ok,) = address(nft).call(abi.encodeCall(IERC721.setApprovalForAll, (target, true)));
        } else if (action % 6 == 4) {
            (ok,) = address(nft).call(abi.encodeCall(AnyCollection.burn, (id)));
        } else {
            (ok,) = address(nft).call(abi.encodeCall(AnyCollection.mint, (bytes32(0))));
        }
    }

    /// Rule 1: after any successful action, every holder and every approved operator of the
    /// token is an agent or a venue.
    function check_HoldersAndOperatorsAreAgents(
        bool aAgent,
        bool aVenue,
        bool bAgent,
        bool bVenue,
        bool cAgent,
        bool cVenue,
        uint8 action,
        uint8 who,
        uint8 towards
    ) public {
        _setUp(aAgent, aVenue, bAgent, bVenue, cAgent, cVenue);
        address caller = _pick(who);
        address target = _pick(towards);
        address holderBefore = nft.ownerOf(id);
        if (!_act(action, caller, target)) return;

        (bool exists, bytes memory data) = address(nft).staticcall(abi.encodeCall(IERC721.ownerOf, (id)));
        if (exists) {
            address holder = abi.decode(data, (address));
            if (holder != holderBefore) assert(_allowed(holder));
            address approved = nft.getApproved(id);
            if (approved != address(0)) assert(_allowed(approved));
        }
        if (nft.isApprovedForAll(A, target)) assert(_allowed(target));
        // A freshly minted token belongs to an agent or venue.
        uint256 last = nft.lastId();
        if (last != id) assert(_allowed(nft.ownerOf(last)));
    }

    /// Rule 2: an account that is neither agent nor venue changes nothing.
    function check_NonAgentsCannotAct(
        bool aAgent,
        bool aVenue,
        bool bAgent,
        bool bVenue,
        bool cAgent,
        bool cVenue,
        uint8 action,
        uint8 who,
        uint8 towards
    ) public {
        _setUp(aAgent, aVenue, bAgent, bVenue, cAgent, cVenue);
        address caller = _pick(who);
        vm.assume(!_allowed(caller));
        assert(!_act(action, caller, _pick(towards)));
    }

    /// Rule 3: a token only changes holder if the new holder pulled it, or a venue moved it.
    /// And a token whose holder is no longer recognised does not move, except by itself.
    function check_NoUnsolicitedTokensAndFrozenTokensStay(
        bool aAgent,
        bool aVenue,
        bool bAgent,
        bool bVenue,
        bool cAgent,
        bool cVenue,
        uint8 action,
        uint8 who,
        uint8 towards
    ) public {
        _setUp(aAgent, aVenue, bAgent, bVenue, cAgent, cVenue);
        address caller = _pick(who);
        address target = _pick(towards);
        vm.assume(action % 6 < 2); // the two transfer functions
        if (!_act(action, caller, target)) return;
        if (target != A) {
            assert(caller == target || reg.isVenue(caller));
            assert(caller == A || _allowed(A));
        }
    }
}

/// Registry with an enrollment verifier: no enrollment without the verifier's approval of
/// that exact digest, whatever the arguments.
contract Verifier1271 {
    mapping(bytes32 => bool) public ok;

    function approve(bytes32 digest) external {
        ok[digest] = true;
    }

    function isValidSignature(bytes32 hash, bytes calldata) external view returns (bytes4) {
        return ok[hash] ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}

/// A verifier that approves everything: with it in force, only a halt can stop an enrollment.
contract YesVerifier {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0x1626ba7e;
    }
}

contract RegistryProps is Test {
    function check_EnrollmentNeedsTheVerifiersApproval(
        bytes32 approvedDigest,
        uint256 agentId,
        address key,
        bytes32 evidence,
        uint64 deadline,
        address sponsor
    ) public {
        Verifier1271 verifier = new Verifier1271();
        address[] memory att = new address[](1);
        att[0] = address(0xA77E);
        AttestedAgentRegistry reg =
            new AttestedAgentRegistry(att, 1, 0, 30 days, 7 days, IERC721(address(0)), address(verifier));
        verifier.approve(approvedDigest);

        bytes32 digest = reg.hashEnrollment(agentId, key, evidence, sponsor, 0, deadline); // fresh registry: nonce 0
        vm.prank(sponsor);
        (bool ok,) = address(reg)
            .call(abi.encodeCall(AttestedAgentRegistry.enroll, (agentId, key, evidence, deadline, new bytes[](0))));
        if (ok) assert(digest == approvedDigest);
    }

    // ------------------------------------------------------------ notice delay

    uint256 constant ATTESTER = 0xA77E57E2;
    uint64 constant NEVER = type(uint64).max; // deadline of the attesters' signatures

    /// Keys last one second more than the notice delay, the shortest life the registry accepts.
    function _registry(uint64 start, uint64 delay, address verifier) internal returns (AttestedAgentRegistry) {
        vm.warp(start);
        address[] memory att = new address[](1);
        att[0] = vm.addr(ATTESTER);
        return new AttestedAgentRegistry(att, 1, 0, delay + 1, delay, IERC721(address(0)), verifier);
    }

    function _signed(bytes32 digest) internal pure returns (bytes[] memory sigs) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTER, digest);
        sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
    }

    /// A verifier to announce: a contract, or address(0) for "attesters sign".
    function _verifier(bool none) internal returns (address) {
        return none ? address(0) : address(new YesVerifier());
    }

    /// Two decisions on a venue, each an approval or a removal, at any two times, with any
    /// notice delay: at any later time the venue is in force only if the last decision approved
    /// it and the delay has passed since the approval that still stands.
    function check_VenueOnlyAfterItsNotice(uint64 delay, uint64 t1, uint64 t2, uint64 t3, bool first, bool second)
        public
    {
        vm.assume(0 < t1 && t1 <= t2 && t2 <= t3 && uint256(t3) + delay < type(uint64).max);
        AttestedAgentRegistry reg = _registry(t1, delay, address(0));
        address venue = address(new YesVerifier()); // any contract: a venue must hold code
        assert(!reg.isVenue(venue));
        reg.setVenue(venue, first, 0, NEVER, _signed(reg.hashVenue(venue, first, 0, NEVER)));
        vm.warp(t2);
        reg.setVenue(venue, second, 0, NEVER, _signed(reg.hashVenue(venue, second, 0, NEVER)));
        vm.warp(t3);
        uint256 approvedAt = first ? t1 : t2;
        assert(reg.isVenue(venue) == (second && t3 >= approvedAt + delay));
    }

    /// Any first decision on the verifier (a replacement or a halt), then a replacement: until
    /// its notice has passed, the registry reports the same verifier and the same halt as just
    /// before it; afterwards the new verifier is in force and nothing is halted.
    function check_VerifierOnlyAfterItsNotice(
        uint64 delay,
        uint64 t1,
        uint64 t2,
        uint64 t3,
        bool haltFirst,
        bool firstIsNone,
        bool secondIsNone
    ) public {
        vm.assume(0 < t1 && t1 <= t2 && t2 <= t3 && uint256(t3) + delay < type(uint64).max);
        AttestedAgentRegistry reg = _registry(t1, delay, address(0));
        address v1 = _verifier(firstIsNone);
        address v2 = _verifier(secondIsNone);
        if (haltFirst) reg.haltEnrollments(0, NEVER, _signed(reg.hashHalt(0, NEVER)));
        else reg.setEnrollmentVerifier(v1, 0, NEVER, _signed(reg.hashVerifier(v1, 0, NEVER)));
        vm.warp(t2);
        address before = reg.enrollmentVerifier();
        bool haltedBefore = reg.enrollmentHalted();
        reg.setEnrollmentVerifier(v2, 0, NEVER, _signed(reg.hashVerifier(v2, 0, NEVER)));
        vm.warp(t3);
        if (t3 >= uint256(t2) + delay) {
            assert(reg.enrollmentVerifier() == v2 && !reg.enrollmentHalted());
        } else {
            assert(reg.enrollmentVerifier() == before && reg.enrollmentHalted() == haltedBefore);
        }
    }

    /// With a verifier that approves everything, and whatever was announced before: once the
    /// attesters have halted enrollments, the registry reports the halt at any later time and
    /// no enrollment passes, whatever its arguments.
    function check_NoEnrollmentWhileHalted(
        uint64 delay,
        uint64 t1,
        uint64 t2,
        uint64 t3,
        bool announcedIsNone,
        uint256 agentId,
        address key,
        address sponsor
    ) public {
        vm.assume(0 < t1 && t1 <= t2 && t2 <= t3 && uint256(t3) + delay < type(uint64).max);
        AttestedAgentRegistry reg = _registry(t1, delay, address(new YesVerifier()));
        address v1 = _verifier(announcedIsNone);
        reg.setEnrollmentVerifier(v1, 0, NEVER, _signed(reg.hashVerifier(v1, 0, NEVER)));
        vm.warp(t2);
        reg.haltEnrollments(0, NEVER, _signed(reg.hashHalt(0, NEVER)));
        vm.warp(t3);
        assert(reg.enrollmentHalted());
        vm.prank(sponsor);
        (bool ok,) = address(reg)
            .call(abi.encodeCall(AttestedAgentRegistry.enroll, (agentId, key, 0, type(uint64).max, new bytes[](0))));
        assert(!ok);
    }

    // ------------------------------------------------------------ attesters

    uint256 constant SECOND = 0xB0B0B0B0;
    uint256 constant THIRD = 0xC0C0C0C0;

    function _sole(uint256 pk) internal pure returns (address[] memory set) {
        set = new address[](1);
        set[0] = vm.addr(pk);
    }

    function _signedBy(uint256 pk, bytes32 digest) internal pure returns (bytes[] memory sigs) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
    }

    /// Whether a halt, a decision reserved to the attesters, passes with these signatures.
    function _halts(AttestedAgentRegistry reg, bytes[] memory sigs) internal returns (bool ok) {
        (ok,) = address(reg).call(abi.encodeCall(AttestedAgentRegistry.haltEnrollments, (0, NEVER, sigs)));
    }

    function _typed(AttestedAgentRegistry reg, bytes32 structHash) internal view returns (bytes32) {
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

    /// What a member of set `set` signs to halt enrollments, on a registry never halted.
    function _haltDigest(AttestedAgentRegistry reg, uint256 set) internal view returns (bytes32) {
        bytes32 kind = keccak256("Halt(bytes32 evidenceHash,uint256 nonce,uint64 deadline,uint256 attesterSet)");
        return _typed(reg, keccak256(abi.encode(kind, bytes32(0), uint256(0), NEVER, set)));
    }

    /// What a member of set `set` signs to hand over to `member` alone, as the second handover.
    function _handoverDigest(AttestedAgentRegistry reg, address member, uint256 set) internal view returns (bytes32) {
        bytes32 kind = keccak256(
            "Attesters(address[] attesters,uint256 threshold,bytes32 evidenceHash,uint256 nonce,uint64 deadline,uint256 attesterSet)"
        );
        return _typed(
            reg,
            keccak256(abi.encode(kind, keccak256(abi.encode(member)), uint256(1), bytes32(0), uint256(1), NEVER, set))
        );
    }

    /// One attester hands over to a second one; then whoever is in force hands over to a third.
    /// At any later time the registry names exactly one of the three as attester, the third
    /// once its notice has passed and until then the one in force when it was announced. A
    /// halt naming the set in force and signed by either of the two others is refused. Sets
    /// of one member, threshold 1. That a signature naming another set is refused rests on the
    /// signature scheme, which the prover does not model: the tests show it.
    /// Every signature is made before the paths split on time: halmos 0.3.3 ties a signature
    /// to its signer only on the path where it is first made. That the attester in force does
    /// decide is shown by the tests, not here: the prover also follows the path where a
    /// signature is refused for its form.
    function check_AttestersOnlyAfterTheirNotice(uint64 delay, uint64 t1, uint64 t2, uint64 t3) public {
        vm.assume(0 < t1 && t1 <= t2 && t2 <= t3 && uint256(t3) + delay < type(uint64).max);
        AttestedAgentRegistry reg = _registry(t1, delay, address(0));
        uint256[3] memory keys = [ATTESTER, SECOND, THIRD];
        // halt[3 * (set - 1) + key]: a halt naming `set`, signed by `key`.
        bytes[][9] memory halt;
        for (uint256 set = 1; set <= 3; ++set) {
            for (uint256 k; k < 3; ++k) {
                halt[3 * (set - 1) + k] = _signedBy(keys[k], _haltDigest(reg, set));
            }
        }
        assert(_haltDigest(reg, 1) == reg.hashHalt(0, NEVER));
        // The second handover, to the third: by the first naming set 1, or by the second naming
        // set 2; accepted by the third in both cases.
        address[] memory next = _sole(THIRD);
        bytes32[2] memory digest = [_handoverDigest(reg, next[0], 1), _handoverDigest(reg, next[0], 2)];
        bytes[][2] memory handover = [_signedBy(ATTESTER, digest[0]), _signedBy(SECOND, digest[1])];
        bytes[][2] memory accepted = [_signedBy(THIRD, digest[0]), _signedBy(THIRD, digest[1])];
        address[] memory second = _sole(SECOND);
        bytes32 first = reg.hashAttesters(second, 1, 0, NEVER);
        reg.setAttesters(second, 1, 0, NEVER, _signedBy(ATTESTER, first), _signedBy(SECOND, first));

        vm.warp(t2);
        uint256 inForce = t2 >= uint256(t1) + delay ? 1 : 0; // index of the attester in force, and of its set
        assert(reg.hashAttesters(next, 1, 0, NEVER) == digest[inForce]);
        reg.setAttesters(next, 1, 0, NEVER, handover[inForce], accepted[inForce]);
        vm.warp(t3);
        if (t3 >= uint256(t2) + delay) inForce = 2;
        assert(reg.attesterSet() == inForce + 1);
        assert(reg.threshold() == 1);
        assert(_haltDigest(reg, inForce + 1) == reg.hashHalt(0, NEVER));
        for (uint256 k; k < 3; ++k) {
            assert(reg.isAttester(vm.addr(keys[k])) == (k == inForce));
        }
        for (uint256 k; k < 3; ++k) {
            if (k != inForce) assert(!_halts(reg, halt[3 * inForce + k]));
        }
    }
}
