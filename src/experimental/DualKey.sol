// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @title A session key held by two machines: it acts only when both sign.
/// @notice Experimental, unaudited. For an agent whose program runs on hardware from two makers
/// (for instance Intel TDX and AWS Nitro): each machine creates its own key, and this contract
/// is enrolled as the agent's session key. Breaking one kind of chip then gives half a key.
/// @dev Anyone may submit an order; only the two signatures count. Orders are EIP-712 typed
/// data bound to this contract, with a nonce and a deadline. `isValidSignature` (ERC-1271)
/// accepts the two signatures of a `DualMessage`, concatenated A then B.
contract DualKey is EIP712 {
    bytes32 private constant ACT_TYPEHASH = keccak256("Act(address target,bytes data,uint256 nonce,uint64 deadline)");
    bytes32 private constant MESSAGE_TYPEHASH = keccak256("DualMessage(bytes32 hash)");

    address public immutable keyA;
    address public immutable keyB;
    uint256 public nonce;

    error BadKeys();
    error NotBoth();
    error Expired();

    constructor(address a, address b) EIP712("DualKey", "1") {
        if (a == address(0) || b == address(0) || a == b) revert BadKeys();
        keyA = a;
        keyB = b;
    }

    /// Calls `target` (usually the agent's account) once both keys have signed the order.
    function act(address target, bytes calldata data, uint64 deadline, bytes calldata sigA, bytes calldata sigB)
        external
        returns (bytes memory)
    {
        if (deadline < block.timestamp) revert Expired();
        bytes32 d = actDigest(target, data, nonce++, deadline);
        if (!_signed(keyA, d, sigA) || !_signed(keyB, d, sigB)) revert NotBoth();
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        return ret;
    }

    function actDigest(address target, bytes calldata data, uint256 nonce_, uint64 deadline)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(keccak256(abi.encode(ACT_TYPEHASH, target, keccak256(data), nonce_, deadline)));
    }

    function messageDigest(bytes32 hash) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(MESSAGE_TYPEHASH, hash)));
    }

    /// ERC-1271. `sig` is the 65-byte signature of key A followed by that of key B.
    function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
        if (sig.length != 130) return 0xffffffff;
        bytes32 d = messageDigest(hash);
        return _signed(keyA, d, sig[:65]) && _signed(keyB, d, sig[65:]) ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }

    function _signed(address key, bytes32 d, bytes calldata sig) private pure returns (bool) {
        (address s, ECDSA.RecoverError err,) = ECDSA.tryRecover(d, sig);
        return err == ECDSA.RecoverError.NoError && s == key;
    }
}
