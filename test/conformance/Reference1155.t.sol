// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IAgentRegistry} from "../../src/IAgentRegistry.sol";
import {ERC1155AgentOnly} from "../../src/ERC1155AgentOnly.sol";
import {ERC1155AgentOnlyConformance} from "./ERC1155AgentOnlyConformance.sol";

/// The smallest ERC-1155 collection on our profile: a mint of a new id to oneself, a burn by the
/// holder or its operator.
contract Reference1155 is ERC1155AgentOnly {
    uint256 public lastId;

    constructor(IAgentRegistry r) ERC1155("") ERC1155AgentOnly(r) {}

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
}

contract Reference1155ConformanceTest is ERC1155AgentOnlyConformance {
    function _deploy(IAgentRegistry r) internal override returns (address) {
        return address(new Reference1155(r));
    }

    function _mintToSelf(address, uint256 amount) internal override returns (uint256) {
        return Reference1155(address(token)).mint(amount);
    }

    function _hasBurn() internal pure override returns (bool) {
        return true;
    }

    function _burn(address, address holder, uint256 id, uint256 amount) internal override {
        Reference1155(address(token)).burn(holder, id, amount);
    }
}
