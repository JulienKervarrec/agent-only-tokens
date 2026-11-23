// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IDcapAttestation, TdxQuoteVerifier} from "./TdxQuoteVerifier.sol";

/// @title Enrollment verifier for dstack agents whose MRCONFIGID is in format 3 (dstack OS 0.6).
/// @notice Unaudited draft.
/// @dev In format 3, MRCONFIGID is the byte 3 followed by
/// `sha256("dstack-mr-config-v3:" || 0x00 || document)`, where the document is a JSON text that
/// names the application, the compose hash, the instance and the key provider
/// (`dstack-types/src/mr_config.rs`, read at dstack v0.6.4). The instance is in it, so the field
/// differs on every machine and `DstackConfigIdVerifier`, which approves the whole field, can
/// approve one machine at a time only.
///
/// This verifier approves a program instead: a base image, a compose hash and a key provider.
/// The caller gives the application id and the instance id of the machine; the contract writes
/// the one document it accepts around them and requires the quote's field to be its hash. That
/// document is the canonical one Phala Cloud produced on 23 November 2026: the seven fields
/// below, in that order, no init script, the key provider `kms`. A document with another shape
/// (other fields, another order, a GPU policy, init scripts, another kind of key provider) has
/// another hash and is refused. Nothing is parsed.
///
/// Trusted beyond `TdxQuoteVerifier`: the approved base image refuses to boot unless the
/// document's compose hash is the one it loads (`verify_mr_config_v3_document` in dstack's
/// `dstack-util`). The application id and the instance id are not restricted: they do not
/// change what runs. RTMR3 is not read.
contract DstackDocumentVerifier is TdxQuoteVerifier {
    uint256 private constant MR_CONFIG_ID = 184; // 48 bytes: format, a 32-byte hash, padding
    uint256 private constant BEFORE = 120; // attributes, features, MRTD: 64 bytes
    uint256 private constant BEFORE_LENGTH = 64;
    uint256 private constant AFTER = 232; // owner fields, RTMR0 to RTMR2: 240 bytes
    uint256 private constant AFTER_LENGTH = 240;
    bytes16 private constant HEX = "0123456789abcdef";

    /// Approved programs, as `programOf`. Fixed at deployment.
    mapping(bytes32 => bool) public isApprovedCode;

    error BadConfigId();

    constructor(IDcapAttestation dcap_, uint8 acceptedTcb_, bytes32[] memory approvedCode)
        TdxQuoteVerifier(dcap_, acceptedTcb_)
    {
        if (approvedCode.length == 0) revert BadConfig();
        for (uint256 i; i < approvedCode.length; ++i) {
            isApprovedCode[approvedCode[i]] = true;
        }
    }

    /// Verifies a quote from a machine that runs an approved program and approves the digest it
    /// carries. `appId` and `instanceId` are the machine's; `composeHash` and `keyProviderId`
    /// are the program's.
    function attest(
        bytes calldata quote,
        bytes20 appId,
        bytes20 instanceId,
        bytes32 composeHash,
        bytes calldata keyProviderId
    ) external payable returns (bytes32 digest) {
        bytes memory output;
        (output, digest) = _verify(quote);
        // The image first: it checks that the output holds a whole report body.
        bytes32 code = programOf(imageOf(output), composeHash, keyProviderId);
        if (keccak256(configIdOf(appId, instanceId, composeHash, keyProviderId)) != keccak256(_configId(output))) {
            revert BadConfigId();
        }
        if (!isApprovedCode[code]) revert UnknownCode(code);
        _approve(digest, code, quote);
    }

    /// The identity of a program: base image, compose hash and key provider.
    function programOf(bytes32 image, bytes32 composeHash, bytes calldata keyProviderId) public pure returns (bytes32) {
        return keccak256(abi.encode(image, composeHash, keccak256(keyProviderId)));
    }

    /// The base image of a verified output: everything the processor measured at boot except
    /// MRCONFIGID (attributes, features, MRTD, owner fields, RTMR0 to RTMR2).
    function imageOf(bytes memory output) public pure returns (bytes32) {
        return keccak256(abi.encode(_hashBody(output, BEFORE, BEFORE_LENGTH), _hashBody(output, AFTER, AFTER_LENGTH)));
    }

    /// The document this verifier accepts for a machine.
    function documentOf(bytes20 appId, bytes20 instanceId, bytes32 composeHash, bytes calldata keyProviderId)
        public
        pure
        returns (bytes memory)
    {
        return bytes.concat(
            '{"app_id":"',
            _hex(abi.encodePacked(appId)),
            '","compose_hash":"',
            _hex(abi.encodePacked(composeHash)),
            '","init_script_hashes":[],"instance_id":"',
            _hex(abi.encodePacked(instanceId)),
            '","key_provider":"kms","key_provider_id":"',
            _hex(keyProviderId),
            '","version":3}'
        );
    }

    /// The MRCONFIGID of a machine whose document is `documentOf`: 3, the hash, zeros.
    function configIdOf(bytes20 appId, bytes20 instanceId, bytes32 composeHash, bytes calldata keyProviderId)
        public
        pure
        returns (bytes memory)
    {
        bytes32 hash = sha256(
            bytes.concat("dstack-mr-config-v3:", bytes1(0), documentOf(appId, instanceId, composeHash, keyProviderId))
        );
        return bytes.concat(bytes1(0x03), hash, bytes15(0));
    }

    function _configId(bytes memory output) private pure returns (bytes memory field) {
        field = new bytes(48);
        for (uint256 i; i < 48; ++i) {
            field[i] = output[BODY + MR_CONFIG_ID + i];
        }
    }

    function _hex(bytes memory data) private pure returns (bytes memory out) {
        out = new bytes(2 * data.length);
        for (uint256 i; i < data.length; ++i) {
            out[2 * i] = HEX[uint8(data[i]) >> 4];
            out[2 * i + 1] = HEX[uint8(data[i]) & 0x0f];
        }
    }
}
