// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IDcapAttestation, TdxQuoteVerifier} from "./TdxQuoteVerifier.sol";

/// @title Enrollment verifier: the agent proves it runs approved code in an Intel TDX machine.
/// @notice Unaudited draft.
/// @dev The code is identified by everything the processor measured: the machine's attributes
/// and enabled features, its boot measurement, its owner fields and its four runtime registers.
/// Fits images whose measurements are the same for every instance. For dstack, whose last
/// register differs per instance, use `DstackEnrollmentVerifier`.
contract TdxEnrollmentVerifier is TdxQuoteVerifier {
    uint256 private constant MEASURED = 120;
    uint256 private constant MEASURED_LENGTH = 400;

    /// Approved agent code, as `codeOf` the verified output. Fixed at deployment.
    mapping(bytes32 => bool) public isApprovedCode;

    constructor(IDcapAttestation dcap_, uint8 acceptedTcb_, bytes32[] memory approvedCode)
        TdxQuoteVerifier(dcap_, acceptedTcb_)
    {
        if (approvedCode.length == 0) revert BadConfig();
        for (uint256 i; i < approvedCode.length; ++i) {
            isApprovedCode[approvedCode[i]] = true;
        }
    }

    /// Verifies a quote from approved code and approves the digest it carries.
    function attest(bytes calldata quote) external payable returns (bytes32 digest) {
        bytes memory output;
        (output, digest) = _verify(quote);
        bytes32 code = codeOf(output);
        if (!isApprovedCode[code]) revert UnknownCode(code);
        _approve(digest, code, quote);
    }

    /// The identity of the code in a verified output.
    function codeOf(bytes memory output) public pure returns (bytes32) {
        return _hashBody(output, MEASURED, MEASURED_LENGTH);
    }
}
