// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IAgentRegistry} from "../../src/IAgentRegistry.sol";
import {ERC721AgentOnly} from "../../src/ERC721AgentOnly.sol";
import {ERC721AgentOnlyConformance} from "./ERC721AgentOnlyConformance.sol";

/// The smallest collection on our implementation: one line of inheritance, a mint to self, a burn.
contract ReferenceCollection is ERC721AgentOnly {
    uint256 public lastId;

    constructor(IAgentRegistry r) ERC721("Reference", "REF") ERC721AgentOnly(r) {}

    function mint() external returns (uint256 id) {
        id = ++lastId;
        _mint(msg.sender, id);
    }

    function burn(uint256 id) external {
        _checkAuthorized(_ownerOf(id), msg.sender, id);
        _burn(id);
    }
}

/// Our implementation passes the conformance suite.
contract ReferenceConformanceTest is ERC721AgentOnlyConformance {
    function _deploy(IAgentRegistry r) internal override returns (address) {
        return address(new ReferenceCollection(r));
    }

    function _mintToSelf(address) internal override returns (uint256) {
        return ReferenceCollection(address(token)).mint();
    }

    function _hasBurn() internal pure override returns (bool) {
        return true;
    }

    function _burn(address, uint256 id) internal override {
        ReferenceCollection(address(token)).burn(id);
    }
}
