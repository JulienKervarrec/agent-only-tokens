// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IDcapAttestation, TdxQuoteVerifier} from "./TdxQuoteVerifier.sol";

/// @title Enrollment verifier for dstack agents, reading the code identity from the quote itself.
/// @notice Unaudited draft.
/// @dev Since dstack 0.5.1 the host can set the quote's MRCONFIGID field, and the dstack OS
/// refuses to boot unless it matches what the OS loads (`verify_mr_config_id` in dstack's
/// `dstack-util`). Its first byte is a format: 1, the compose hash; 2, a hash of the compose
/// hash, the application id and the key provider; 3, a hash of a document that holds the compose
/// hash and may pin more. Every format binds the compose hash. The processor signs MRCONFIGID
/// with the boot measurements, so one hash over attributes, features, MRTD, MRCONFIGID (format
/// included), owner fields and RTMR0 to RTMR2 identifies both the base image and the
/// application, and the approved list decides which format and which content are accepted.
/// No event log, no SHA-384.
///
/// RTMR3 is not read: it holds the instance id and what the application logs, and the compose
/// hash a second time. Trusted beyond `TdxQuoteVerifier`: the approved base image enforces the
/// MRCONFIGID check. An unset MRCONFIGID (all zeros, which dstack tolerates without checking
/// anything) and formats dstack does not define are refused.
contract DstackConfigIdVerifier is TdxQuoteVerifier {
    uint256 private constant MEASURED = 120; // attributes .. RTMR2, MRCONFIGID included
    uint256 private constant MEASURED_LENGTH = 352;
    uint256 private constant MR_CONFIG_ID = 184; // 48 bytes: format, a 32-byte hash, padding

    /// Approved code identities (base image and MRCONFIGID), as `codeOf`. Fixed at deployment.
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

    /// Verifies a quote from an approved dstack application and approves the digest it carries.
    function attest(bytes calldata quote) external payable returns (bytes32 digest) {
        bytes memory output;
        (output, digest) = _verify(quote);
        _approveConfigId(output, digest, quote);
    }

    /// Approves `digest` if the verified output comes from approved code. `evidence` is what was
    /// submitted, hashed into the event.
    function _approveConfigId(bytes memory output, bytes32 digest, bytes calldata evidence) internal {
        uint8 format = uint8(output[BODY + MR_CONFIG_ID]);
        if (format == 0 || format > 3) revert BadConfigId();
        bytes32 code = codeOf(output);
        if (!isApprovedCode[code]) revert UnknownCode(code);
        _approve(digest, code, evidence);
    }

    /// The identity of the code in a verified output: base image and MRCONFIGID together.
    function codeOf(bytes memory output) public pure returns (bytes32) {
        return _hashBody(output, MEASURED, MEASURED_LENGTH);
    }

    /// The compose hash a verified output carries in MRCONFIGID, in format 1. Formats 2 and 3
    /// carry a hash of it with other fields instead.
    function composeHashOf(bytes memory output) public pure returns (bytes32) {
        if (output.length < BODY + TD10_BODY_LENGTH) revert UnsupportedReport();
        if (output[BODY + MR_CONFIG_ID] != 0x01) revert BadConfigId();
        return _word(output, BODY + MR_CONFIG_ID + 1);
    }
}
