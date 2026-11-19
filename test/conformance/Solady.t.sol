// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IAgentRegistry} from "../../src/IAgentRegistry.sol";
import {SoladyCollection} from "./solady/SoladyCollection.sol";
import {ERC721AgentOnlyConformance} from "./ERC721AgentOnlyConformance.sol";

/// Step 4.2: a second implementation, written on Solady by an independent agent that saw only
/// the text of the proposal (docs/erc), runs through the same conformance suite.
contract SoladyConformanceTest is ERC721AgentOnlyConformance {
    function _deploy(IAgentRegistry r) internal override returns (address) {
        return address(new SoladyCollection(r));
    }

    function _mintToSelf(address) internal override returns (uint256) {
        return SoladyCollection(address(token)).mint();
    }

    function _hasBurn() internal pure override returns (bool) {
        return true;
    }

    function _burn(address, uint256 id) internal override {
        SoladyCollection(address(token)).burn(id);
    }
}
