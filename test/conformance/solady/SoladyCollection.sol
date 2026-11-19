// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {LibString} from "solady/utils/LibString.sol";
import {IAgentRegistry} from "../../../src/IAgentRegistry.sol";
import {SoladyAgentOnly} from "./SoladyAgentOnly.sol";

/// @notice Minimal Agent-Only collection: anyone recognised mints the next id to itself.
contract SoladyCollection is SoladyAgentOnly {
    uint256 public nextId = 1;

    constructor(IAgentRegistry registry_) SoladyAgentOnly(registry_) {}

    function name() public pure override returns (string memory) {
        return "Agent Only";
    }

    function symbol() public pure override returns (string memory) {
        return "AGO";
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (!_exists(id)) revert TokenDoesNotExist();
        return string.concat("agent-only://", LibString.toString(id));
    }

    /// Mints the next id to the caller (rules 2-4 apply through the hook).
    function mint() external returns (uint256 id) {
        id = nextId++;
        _mint(msg.sender, id);
    }

    /// Burn by the holder or an approved operator (rules 2 and 7 apply through the hook).
    function burn(uint256 id) external {
        _burn(msg.sender, id);
    }
}
