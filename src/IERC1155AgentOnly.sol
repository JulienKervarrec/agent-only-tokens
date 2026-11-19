// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IAgentRegistry} from "./IAgentRegistry.sol";

/// A compliant ERC-1155 is a full ERC-1155 that exposes its registry. The function is the same
/// as for the ERC-721 profile, so the ERC-165 identifier is the same (`0x0d1cfcae`); which
/// profile a token follows is told by the token interface it also advertises.
interface IERC1155AgentOnly {
    function agentRegistry() external view returns (IAgentRegistry);
}
