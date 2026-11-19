// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IAgentRegistry} from "../src/IAgentRegistry.sol";
import {IERC721AgentOnly} from "../src/IERC721AgentOnly.sol";
import {ERC721AgentOnlyConformance} from "../test/conformance/ERC721AgentOnlyConformance.sol";

/// Deliberately wrong implementations, one missing check each. Each must fail the conformance
/// suite; `tools/conformance.py` runs them (profile `faulty`) and checks that they do.
/// Not part of `forge test`: these tests are meant to fail.
enum Fault {
    NoInterface, // rule 1: does not advertise IERC721AgentOnly
    AnyCaller, // rule 2: does not check the caller
    AnyRecipientViaVenue, // rule 3: a venue may send to anyone
    Push, // rule 4: an agent may push to another agent
    AnyOperator, // rule 5: a human may be approved
    NoClearWhenFrozen, // rule 5: clearing needs the holder to be recognised
    AnyGranter, // rule 5: an unrecognised holder may grant approvals
    NoHolderOnGrant, // rule 5: an operator of an unrecognised holder may grant approvals
    FrozenMoves // rule 7: an unrecognised holder's token moves
}

contract FaultyCollection is ERC721, IERC721AgentOnly {
    IAgentRegistry public immutable override agentRegistry;
    Fault public immutable fault;
    uint256 public lastId;

    constructor(IAgentRegistry r, Fault f) ERC721("Faulty", "BAD") {
        agentRegistry = r;
        fault = f;
    }

    function mint() external returns (uint256 id) {
        id = ++lastId;
        _mint(msg.sender, id);
    }

    function burn(uint256 id) external {
        _checkAuthorized(_ownerOf(id), msg.sender, id);
        _burn(id);
    }

    function supportsInterface(bytes4 id) public view override returns (bool) {
        if (fault != Fault.NoInterface && id == type(IERC721AgentOnly).interfaceId) return true;
        return super.supportsInterface(id);
    }

    function _ok(address a) private view returns (bool) {
        return agentRegistry.isAgent(a) || agentRegistry.isVenue(a);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address caller = _msgSender();
        bool venue = agentRegistry.isVenue(caller);
        if (fault != Fault.AnyCaller && !_ok(caller)) revert("caller");
        address from = _ownerOf(tokenId);
        if (fault != Fault.FrozenMoves && from != address(0) && !_ok(from)) revert("holder");
        if (to != address(0)) {
            if (!(fault == Fault.AnyRecipientViaVenue && venue) && !_ok(to)) revert("recipient");
            if (fault != Fault.Push && !venue && to != caller) revert("push");
        }
        return super._update(to, tokenId, auth);
    }

    function _approve(address to, uint256 tokenId, address auth, bool emitEvent) internal override {
        if (to != address(0)) {
            if (fault != Fault.AnyOperator && !_ok(to)) revert("operator");
            if (fault != Fault.AnyGranter && !_ok(_msgSender())) revert("granter");
            if (fault != Fault.NoHolderOnGrant && fault != Fault.AnyGranter && !_ok(_requireOwned(tokenId))) {
                revert("holder");
            }
        } else if (fault == Fault.NoClearWhenFrozen && !_ok(_msgSender())) {
            revert("clear");
        }
        super._approve(to, tokenId, auth, emitEvent);
    }

    function _setApprovalForAll(address owner, address operator, bool approved) internal override {
        if (approved) {
            if (fault != Fault.AnyOperator && !_ok(operator)) revert("operator");
            if (fault != Fault.AnyGranter && !_ok(owner)) revert("granter");
        } else if (fault == Fault.NoClearWhenFrozen && !_ok(owner)) {
            revert("clear");
        }
        super._setApprovalForAll(owner, operator, approved);
    }
}

    abstract contract FaultySuite is ERC721AgentOnlyConformance {
        function _fault() internal pure virtual returns (Fault);

        function _deploy(IAgentRegistry r) internal override returns (address) {
            return address(new FaultyCollection(r, _fault()));
        }

        function _mintToSelf(address) internal override returns (uint256) {
            return FaultyCollection(address(token)).mint();
        }

        function _hasBurn() internal pure override returns (bool) {
            return true;
        }

        function _burn(address, uint256 id) internal override {
            FaultyCollection(address(token)).burn(id);
        }
    }

    contract FaultyNoInterface is FaultySuite {
        function _fault() internal pure override returns (Fault) {
            return Fault.NoInterface;
        }
    }

    contract FaultyAnyCaller is FaultySuite {
        function _fault() internal pure override returns (Fault) {
            return Fault.AnyCaller;
        }
    }

    contract FaultyAnyRecipientViaVenue is FaultySuite {
        function _fault() internal pure override returns (Fault) {
            return Fault.AnyRecipientViaVenue;
        }
    }

    contract FaultyPush is FaultySuite {
        function _fault() internal pure override returns (Fault) {
            return Fault.Push;
        }
    }

    contract FaultyAnyOperator is FaultySuite {
        function _fault() internal pure override returns (Fault) {
            return Fault.AnyOperator;
        }
    }

    contract FaultyNoClearWhenFrozen is FaultySuite {
        function _fault() internal pure override returns (Fault) {
            return Fault.NoClearWhenFrozen;
        }
    }

    contract FaultyAnyGranter is FaultySuite {
        function _fault() internal pure override returns (Fault) {
            return Fault.AnyGranter;
        }
    }

    contract FaultyNoHolderOnGrant is FaultySuite {
        function _fault() internal pure override returns (Fault) {
            return Fault.NoHolderOnGrant;
        }
    }

    contract FaultyFrozenMoves is FaultySuite {
        function _fault() internal pure override returns (Fault) {
            return Fault.FrozenMoves;
        }
    }
