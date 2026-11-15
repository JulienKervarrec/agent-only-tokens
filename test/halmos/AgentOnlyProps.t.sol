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
            (ok,) = address(nft).call(abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", A, target, id));
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
        bool aAgent, bool aVenue, bool bAgent, bool bVenue, bool cAgent, bool cVenue,
        uint8 action, uint8 who, uint8 towards
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
        bool aAgent, bool aVenue, bool bAgent, bool bVenue, bool cAgent, bool cVenue,
        uint8 action, uint8 who, uint8 towards
    ) public {
        _setUp(aAgent, aVenue, bAgent, bVenue, cAgent, cVenue);
        address caller = _pick(who);
        vm.assume(!_allowed(caller));
        assert(!_act(action, caller, _pick(towards)));
    }

    /// Rule 3: a token only changes holder if the new holder pulled it, or a venue moved it.
    /// And a token whose holder is no longer recognised does not move, except by itself.
    function check_NoUnsolicitedTokensAndFrozenTokensStay(
        bool aAgent, bool aVenue, bool bAgent, bool bVenue, bool cAgent, bool cVenue,
        uint8 action, uint8 who, uint8 towards
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

contract RegistryProps is Test {
    function check_EnrollmentNeedsTheVerifiersApproval(
        bytes32 approvedDigest, uint256 agentId, address key, bytes32 evidence, uint64 deadline, address sponsor
    ) public {
        Verifier1271 verifier = new Verifier1271();
        address[] memory att = new address[](1);
        att[0] = address(0xA77E);
        AttestedAgentRegistry reg =
            new AttestedAgentRegistry(att, 1, 0, 30 days, IERC721(address(0)), address(verifier));
        verifier.approve(approvedDigest);

        bytes32 digest = reg.hashEnrollment(agentId, key, evidence, sponsor, 0, deadline); // fresh registry: nonce 0
        vm.prank(sponsor);
        (bool ok,) = address(reg).call(
            abi.encodeCall(AttestedAgentRegistry.enroll, (agentId, key, evidence, deadline, new bytes[](0)))
        );
        if (ok) assert(digest == approvedDigest);
    }
}
