// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IAgentKeys {
    function keyOf(uint256 agentId) external view returns (address);
}

/// @title An agent's account: a wallet with no human owner.
/// @notice Unaudited draft. Only the session key the registry recognises for this agent
/// can make it act. The key changes at each enrollment; the account and its assets stay.
contract AgentAccount {
    IAgentKeys public immutable registry;
    uint256 public immutable agentId;
    uint256 public nonce;

    error NotKey();
    error Expired();

    constructor(uint256 agentId_) {
        registry = IAgentKeys(msg.sender);
        agentId = agentId_;
    }

    receive() external payable {}

    /// Direct call by the session key.
    function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory) {
        if (msg.sender != registry.keyOf(agentId)) revert NotKey();
        return _call(target, value, data);
    }

    /// Same call, signed by the session key and submitted by any relayer.
    function executeBySig(address target, uint256 value, bytes calldata data, uint64 deadline, bytes calldata sig)
        external
        returns (bytes memory)
    {
        if (deadline < block.timestamp) revert Expired();
        bytes32 digest = execDigest(target, value, data, nonce++, deadline);
        if (!_isKey(digest, sig)) revert NotKey();
        return _call(target, value, data);
    }

    function execDigest(address target, uint256 value, bytes calldata data, uint256 nonce_, uint64 deadline)
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(block.chainid, address(this), target, value, keccak256(data), nonce_, deadline));
    }

    /// ERC-1271: lets the account sign off-chain (orders, payment authorisations).
    function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
        return _isKey(hash, sig) ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _isKey(bytes32 digest, bytes calldata sig) private view returns (bool) {
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, sig);
        address key = registry.keyOf(agentId);
        return err == ECDSA.RecoverError.NoError && key != address(0) && signer == key;
    }

    function _call(address target, uint256 value, bytes calldata data) private returns (bytes memory) {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        return ret;
    }
}
