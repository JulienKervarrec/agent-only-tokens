// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// The only link between an asset and the proof of agent.
interface IAgentRegistry {
    /// True if `account` is the account of an active agent.
    function isAgent(address account) external view returns (bool);
    /// True if `account` is an approved venue contract (swap, loan, staking).
    function isVenue(address account) external view returns (bool);
}
