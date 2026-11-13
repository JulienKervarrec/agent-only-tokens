// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

interface IAgentKeys {
    function keyOf(uint256 agentId) external view returns (address);
}

/// @title An agent's account: a wallet with no human owner.
/// @notice Unaudited draft. Only the session key the registry recognises for this agent
/// can make it act. The key changes at each enrollment; the account and its assets stay.
/// @dev Everything the key signs off-chain is EIP-712 typed data bound to this account:
/// an `Execute` order, or an `AgentMessage` wrapping a hash for ERC-1271. A signature
/// made for one purpose can therefore never be used for the other, nor on another account.
contract AgentAccount is EIP712 {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    bytes32 private constant EXECUTE_TYPEHASH =
        keccak256("Execute(address target,uint256 value,bytes data,uint256 nonce,uint64 deadline)");
    bytes32 private constant MESSAGE_TYPEHASH = keccak256("AgentMessage(bytes32 hash)");

    IAgentKeys public immutable registry;
    uint256 public immutable agentId;
    uint256 public nonce;

    error NotKey();
    error Expired();

    constructor(uint256 agentId_) EIP712("AgentAccount", "1") {
        registry = IAgentKeys(msg.sender);
        agentId = agentId_;
    }

    receive() external payable {}

    /// Called by the session key, or by the account itself (relayed batch).
    modifier onlyKey() {
        if (msg.sender != address(this) && msg.sender != registry.keyOf(agentId)) revert NotKey();
        _;
    }

    /// Direct call by the session key.
    function execute(address target, uint256 value, bytes calldata data) external onlyKey returns (bytes memory) {
        return _call(target, value, data);
    }

    /// Several calls, all or nothing. Lets an agent check a condition and act in one transaction.
    function executeBatch(Call[] calldata calls) external onlyKey returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            results[i] = _call(calls[i].target, calls[i].value, calls[i].data);
        }
    }

    /// Same as `execute`, signed by the session key and submitted by any relayer.
    /// To relay a batch, target this account with an `executeBatch` call.
    function executeBySig(address target, uint256 value, bytes calldata data, uint64 deadline, bytes calldata sig)
        external
        returns (bytes memory)
    {
        if (deadline < block.timestamp) revert Expired();
        bytes32 digest = execDigest(target, value, data, nonce++, deadline);
        if (!_isKey(digest, sig)) revert NotKey();
        return _call(target, value, data);
    }

    /// EIP-712 digest of an `Execute` order.
    function execDigest(address target, uint256 value, bytes calldata data, uint256 nonce_, uint64 deadline)
        public
        view
        returns (bytes32)
    {
        return
            _hashTypedDataV4(keccak256(abi.encode(EXECUTE_TYPEHASH, target, value, keccak256(data), nonce_, deadline)));
    }

    /// EIP-712 digest the session key signs to approve `hash` on behalf of this account.
    function messageDigest(bytes32 hash) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(MESSAGE_TYPEHASH, hash)));
    }

    /// ERC-1271: lets the account sign off-chain (orders, payment authorisations).
    function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
        return _isKey(messageDigest(hash), sig) ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
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
