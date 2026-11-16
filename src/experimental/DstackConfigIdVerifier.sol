// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IDcapAttestation, TdxQuoteVerifier} from "./TdxQuoteVerifier.sol";

/// @title Enrollment verifier for dstack agents, reading the code identity from the quote itself.
/// @notice Unaudited draft.
/// @dev Since dstack 0.5.1 the host sets the quote's MRCONFIGID field to `01`, the hash of the
/// application's compose manifest, then zeros, and the dstack OS refuses to boot unless that
/// value matches the manifest it loads (`verify_mr_config_id` in dstack's `dstack-util`). The
/// processor signs MRCONFIGID with the boot measurements, so one hash over attributes,
/// features, MRTD, MRCONFIGID, owner fields and RTMR0 to RTMR2 identifies both the base image
/// and the application. No event log, no SHA-384.
///
/// RTMR3 is not read: it holds the instance id and what the application logs, and the compose
/// hash a second time. Trusted beyond `TdxQuoteVerifier`: the approved base image enforces the
/// MRCONFIGID check. An unset MRCONFIGID (all zeros, which dstack tolerates) and the other
/// formats (2 and 3, which bind more than the compose hash) are refused.
contract DstackConfigIdVerifier is TdxQuoteVerifier {
    uint256 private constant MEASURED = 120; // attributes .. RTMR2, MRCONFIGID included
    uint256 private constant MEASURED_LENGTH = 352;
    uint256 private constant MR_CONFIG_ID = 184; // 48 bytes: format, compose hash, padding

    /// Approved (base image, compose hash) pairs, as `codeOf`. Fixed at deployment.
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
        if (output[BODY + MR_CONFIG_ID] != 0x01) revert BadConfigId();
        bytes32 code = codeOf(output);
        if (!isApprovedCode[code]) revert UnknownCode(code);
        _approve(digest, code, quote);
    }

    /// The identity of the code in a verified output: base image and compose hash together.
    function codeOf(bytes memory output) public pure returns (bytes32) {
        return _hashBody(output, MEASURED, MEASURED_LENGTH);
    }

    /// The compose hash a verified output carries in MRCONFIGID.
    function composeHashOf(bytes memory output) public pure returns (bytes32) {
        if (output.length < BODY + TD10_BODY_LENGTH) revert UnsupportedReport();
        return _word(output, BODY + MR_CONFIG_ID + 1);
    }
}
