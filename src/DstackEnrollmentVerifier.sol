// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IDcapAttestation, TdxQuoteVerifier} from "./TdxQuoteVerifier.sol";
import {Sha384} from "./Sha384.sol";

/// @title Enrollment verifier for agents running on dstack (Intel TDX).
/// @notice Unaudited draft.
/// @dev In dstack, the base image is measured in the boot registers (attributes, features, MRTD,
/// owner fields, RTMR0 to RTMR2), and the application in the last register, RTMR3, as a chain of
/// events: RTMR3 = SHA-384(RTMR3 || event digest), from 48 zero bytes. Among the events is the
/// hash of the application's compose file, which identifies its code, and its instance id,
/// which makes RTMR3 differ for each instance.
///
/// The caller supplies the digests of all RTMR3 events, in order, and which one is the
/// compose-hash event, with its payload. The contract replays the chain, requires it to equal
/// the quote's RTMR3, recomputes the compose-hash event's digest from its payload, and requires
/// that event to come before `boot-mr-done`: events before it are written by the dstack OS,
/// events after it may be written by the application. The code is the pair
/// (base image, compose hash), approved at deployment.
///
/// Digest formats, from dstack's `cc-eventlog` (commit b936f86): V1 is
/// SHA-384(event type, little-endian || ":" || name || ":" || payload); V2 is SHA-384 of the
/// canonical JSON {"name":...,"payload":"<hex>","type":134217729}.
contract DstackEnrollmentVerifier is TdxQuoteVerifier {
    uint256 private constant IMAGE = 120; // attributes, features, MRTD, owner fields, RTMR0-2
    uint256 private constant IMAGE_LENGTH = 352;
    uint256 private constant MAX_EVENTS = 64;
    bytes4 private constant EVENT_TYPE_LE = 0x01000008; // 0x08000001, little-endian

    // SHA-384 digests of the empty `boot-mr-done` event, V1 and V2, split in 32 + 16 bytes.
    bytes32 private constant BOOT_DONE_V1_HIGH = 0x98bd7e6bd3952720b65027fd494834045d06b4a714bf737a06b874638b3ea00f;
    bytes16 private constant BOOT_DONE_V1_LOW = 0xf402f7f583e3e3b05e921c8570433ac6;
    bytes32 private constant BOOT_DONE_V2_HIGH = 0xaeadedb6d47c136395e76aaa640667ed1635429ee9a3795e0c97ad11f809b980;
    bytes16 private constant BOOT_DONE_V2_LOW = 0x5b39ba43d07f2e68cf51facd318d350d;

    /// Approved (base image, compose hash) pairs, as `codeOf`. Fixed at deployment.
    mapping(bytes32 => bool) public isApprovedCode;

    error BadEventLog();

    constructor(IDcapAttestation dcap_, uint8 acceptedTcb_, bytes32[] memory approvedCode)
        TdxQuoteVerifier(dcap_, acceptedTcb_)
    {
        if (approvedCode.length == 0) revert BadConfig();
        for (uint256 i; i < approvedCode.length; ++i) {
            isApprovedCode[approvedCode[i]] = true;
        }
    }

    /// Verifies a quote from an approved dstack application and approves the digest it carries.
    /// `eventDigests`: the 48-byte digests of the RTMR3 events, concatenated, in order.
    /// `composeIndex`, `composeV2`, `composeHash`: position, format and payload of the
    /// compose-hash event.
    function attest(
        bytes calldata quote,
        bytes calldata eventDigests,
        uint256 composeIndex,
        bool composeV2,
        bytes32 composeHash
    ) external payable returns (bytes32 digest) {
        bytes memory output;
        (output, digest) = _verify(quote);
        _checkEventLog(output, eventDigests, composeIndex, composeV2, composeHash);
        bytes32 code = codeOf(output, composeHash);
        if (!isApprovedCode[code]) revert UnknownCode(code);
        _approve(digest, code, quote);
    }

    /// The identity of the code: its base image and its compose hash.
    function codeOf(bytes memory output, bytes32 composeHash) public pure returns (bytes32) {
        return keccak256(abi.encode(_hashBody(output, IMAGE, IMAGE_LENGTH), composeHash));
    }

    /// RTMR3 after extending 48 zero bytes with each 48-byte digest, in order.
    function replay(bytes calldata eventDigests) public pure returns (bytes32 high, bytes16 low) {
        for (uint256 i; i < eventDigests.length / 48; ++i) {
            (high, low) = Sha384.hash(abi.encodePacked(high, low, eventDigests[i * 48:i * 48 + 48]));
        }
    }

    /// Digest of a compose-hash event carrying `composeHash`, in format V1 or V2.
    function composeEventDigest(bytes32 composeHash, bool v2) public pure returns (bytes32, bytes16) {
        if (!v2) return Sha384.hash(abi.encodePacked(EVENT_TYPE_LE, ":compose-hash:", composeHash));
        return Sha384.hash(
            abi.encodePacked('{"name":"compose-hash","payload":"', _hex(composeHash), '","type":134217729}')
        );
    }

    function _checkEventLog(
        bytes memory output,
        bytes calldata eventDigests,
        uint256 composeIndex,
        bool composeV2,
        bytes32 composeHash
    ) private pure {
        uint256 count = eventDigests.length / 48;
        if (eventDigests.length % 48 != 0 || count > MAX_EVENTS || composeIndex >= count) revert BadEventLog();

        // The compose-hash event is the one at `composeIndex`, and the OS wrote it.
        (bytes32 high, bytes16 low) = composeEventDigest(composeHash, composeV2);
        bytes calldata compose = eventDigests[composeIndex * 48:composeIndex * 48 + 48];
        if (bytes32(compose[0:32]) != high || bytes16(compose[32:48]) != low) revert BadEventLog();
        for (uint256 i; i < composeIndex; ++i) {
            if (_isBootDone(eventDigests[i * 48:i * 48 + 48])) revert BadEventLog();
        }

        // The events replay to the quote's RTMR3.
        (high, low) = replay(eventDigests);
        if (high != _word(output, BODY + RTMR3) || low != bytes16(_word(output, BODY + RTMR3 + 32))) {
            revert BadEventLog();
        }
    }

    function _isBootDone(bytes calldata d) private pure returns (bool) {
        bytes32 high = bytes32(d[0:32]);
        bytes16 low = bytes16(d[32:48]);
        return (high == BOOT_DONE_V1_HIGH && low == BOOT_DONE_V1_LOW)
            || (high == BOOT_DONE_V2_HIGH && low == BOOT_DONE_V2_LOW);
    }

    function _hex(bytes32 value) private pure returns (bytes memory out) {
        bytes16 digits = "0123456789abcdef";
        out = new bytes(64);
        for (uint256 i; i < 32; ++i) {
            out[2 * i] = digits[uint8(value[i]) >> 4];
            out[2 * i + 1] = digits[uint8(value[i]) & 0x0f];
        }
    }
}
