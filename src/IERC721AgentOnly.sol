// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IAgentRegistry} from "./IAgentRegistry.sol";

/// A compliant token is a full ERC-721 that exposes its registry.
/// Its ERC-165 identifier is `type(IERC721AgentOnly).interfaceId`.
interface IERC721AgentOnly {
    function agentRegistry() external view returns (IAgentRegistry);
}
