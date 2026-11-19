// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IAgentRegistry} from "../src/IAgentRegistry.sol";
import {IERC1155AgentOnly} from "../src/IERC1155AgentOnly.sol";
import {ERC1155AgentOnlyConformance} from "../test/conformance/ERC1155AgentOnlyConformance.sol";

/// Deliberately wrong ERC-1155 implementations, one missing check each, for the ERC-1155 suite.
enum Fault1155 {
    NoInterface,
    AnyCaller,
    AnyRecipientViaVenue,
    Push,
    AnyOperator,
    NoClearWhenFrozen,
    AnyGranter,
    FrozenMoves
}

contract Faulty1155Collection is ERC1155, IERC1155AgentOnly {
    IAgentRegistry public immutable override agentRegistry;
    Fault1155 public immutable fault;
    uint256 public lastId;

    constructor(IAgentRegistry r, Fault1155 f) ERC1155("") {
        agentRegistry = r;
        fault = f;
    }

    function mint(uint256 amount) external returns (uint256 id) {
        id = ++lastId;
        _mint(msg.sender, id, amount, "");
    }

    function burn(address holder, uint256 id, uint256 amount) external {
        if (holder != msg.sender && !isApprovedForAll(holder, msg.sender)) {
            revert ERC1155MissingApprovalForAll(msg.sender, holder);
        }
        _burn(holder, id, amount);
    }

    function supportsInterface(bytes4 id) public view override returns (bool) {
        if (fault != Fault1155.NoInterface && id == type(IERC1155AgentOnly).interfaceId) return true;
        return super.supportsInterface(id);
    }

    function _ok(address a) private view returns (bool) {
        return agentRegistry.isAgent(a) || agentRegistry.isVenue(a);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override {
        address caller = _msgSender();
        bool venue = agentRegistry.isVenue(caller);
        if (fault != Fault1155.AnyCaller && !_ok(caller)) revert("caller");
        if (fault != Fault1155.FrozenMoves && from != address(0) && !_ok(from)) revert("holder");
        if (to != address(0)) {
            if (!(fault == Fault1155.AnyRecipientViaVenue && venue) && !_ok(to)) revert("recipient");
            if (fault != Fault1155.Push && !venue && to != caller) revert("push");
        }
        super._update(from, to, ids, values);
    }

    function _setApprovalForAll(address owner, address operator, bool approved) internal override {
        if (approved) {
            if (fault != Fault1155.AnyOperator && !_ok(operator)) revert("operator");
            if (fault != Fault1155.AnyGranter && !_ok(owner)) revert("granter");
        } else if (fault == Fault1155.NoClearWhenFrozen && !_ok(owner)) {
            revert("clear");
        }
        super._setApprovalForAll(owner, operator, approved);
    }
}

    abstract contract Faulty1155Suite is ERC1155AgentOnlyConformance {
        function _fault() internal pure virtual returns (Fault1155);

        function _deploy(IAgentRegistry r) internal override returns (address) {
            return address(new Faulty1155Collection(r, _fault()));
        }

        function _mintToSelf(address, uint256 amount) internal override returns (uint256) {
            return Faulty1155Collection(address(token)).mint(amount);
        }

        function _hasBurn() internal pure override returns (bool) {
            return true;
        }

        function _burn(address, address holder, uint256 id, uint256 amount) internal override {
            Faulty1155Collection(address(token)).burn(holder, id, amount);
        }
    }

    contract Faulty1155NoInterface is Faulty1155Suite {
        function _fault() internal pure override returns (Fault1155) {
            return Fault1155.NoInterface;
        }
    }

    contract Faulty1155AnyCaller is Faulty1155Suite {
        function _fault() internal pure override returns (Fault1155) {
            return Fault1155.AnyCaller;
        }
    }

    contract Faulty1155AnyRecipientViaVenue is Faulty1155Suite {
        function _fault() internal pure override returns (Fault1155) {
            return Fault1155.AnyRecipientViaVenue;
        }
    }

    contract Faulty1155Push is Faulty1155Suite {
        function _fault() internal pure override returns (Fault1155) {
            return Fault1155.Push;
        }
    }

    contract Faulty1155AnyOperator is Faulty1155Suite {
        function _fault() internal pure override returns (Fault1155) {
            return Fault1155.AnyOperator;
        }
    }

    contract Faulty1155NoClearWhenFrozen is Faulty1155Suite {
        function _fault() internal pure override returns (Fault1155) {
            return Fault1155.NoClearWhenFrozen;
        }
    }

    contract Faulty1155AnyGranter is Faulty1155Suite {
        function _fault() internal pure override returns (Fault1155) {
            return Fault1155.AnyGranter;
        }
    }

    contract Faulty1155FrozenMoves is Faulty1155Suite {
        function _fault() internal pure override returns (Fault1155) {
            return Fault1155.FrozenMoves;
        }
    }
