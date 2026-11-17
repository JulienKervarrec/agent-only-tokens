// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IDcapAttestation} from "./TdxQuoteVerifier.sol";
import {DstackConfigIdVerifier} from "./DstackConfigIdVerifier.sol";

/// RISC Zero's verifier interface (its router dispatches on the seal's first four bytes).
interface IRiscZeroVerifier {
    function verify(bytes calldata seal, bytes32 imageId, bytes32 journalDigest) external view;
}

/// The quote verifiers behind Automata's DCAP entrypoint, one per quote version.
interface IDcapQuoteVerifiers {
    function quoteVerifiers(uint16 quoteVersion) external view returns (IDcapZkOutput);
}

/// Checks, against Intel's data on chain, the data a zk proof says the quote was checked with.
interface IDcapZkOutput {
    function verifyZkOutput(bytes calldata zkOutput, uint32 tcbEvalNumber)
        external
        view
        returns (bool success, bytes memory output);
}

/// @title The dstack enrollment verifier with a second route: a zero-knowledge proof.
/// @notice Experimental, unaudited.
/// @dev Same approved code, same checks as `DstackConfigIdVerifier`; only the evidence differs.
/// Instead of the quote, which costs about 3.7 million gas to check, anyone submits Automata's
/// DCAP program output and a RISC Zero proof that this program, pinned here by its image id,
/// checked the quote and produced it. Automata's quote verifier then compares the Intel data the
/// program used with the data on chain at the time of the check, and returns the same output as
/// the direct route.
///
/// Trusted beyond the direct route: RISC Zero's proof system and verifier, and Automata's
/// program as built into the pinned image id. Automata compares the Intel data as of the time
/// written in the proof; this contract refuses a proof older than `maxAge`. A new program version
/// means a new verifier, installed through the registry's notice rule.
contract DstackConfigIdZkVerifier is DstackConfigIdVerifier {
    uint256 private constant COLLATERAL = 200; // time of the check (8 bytes) and six data hashes

    IRiscZeroVerifier public immutable zkVerifier;
    bytes32 public immutable program;
    uint64 public immutable maxAge;

    error BadZkOutput();
    error StaleProof(uint64 checkedAt);

    constructor(
        IDcapAttestation dcap_,
        uint8 acceptedTcb_,
        bytes32[] memory approvedCode,
        IRiscZeroVerifier zkVerifier_,
        bytes32 program_,
        uint64 maxAge_
    ) DstackConfigIdVerifier(dcap_, acceptedTcb_, approvedCode) {
        if (address(zkVerifier_) == address(0) || program_ == 0 || maxAge_ == 0) revert BadConfig();
        zkVerifier = zkVerifier_;
        program = program_;
        maxAge = maxAge_;
    }

    /// Verifies a proof that the pinned program checked a quote from an approved dstack
    /// application, and approves the digest the quote carries.
    function attestWithProof(bytes calldata zkOutput, bytes calldata seal) external returns (bytes32 digest) {
        zkVerifier.verify(seal, program, sha256(zkOutput));
        if (zkOutput.length < 2) revert BadZkOutput();
        uint256 end = 2 + uint256(uint16(bytes2(zkOutput[0:2])));
        if (end + COLLATERAL != zkOutput.length) revert BadZkOutput();
        uint64 checkedAt = uint64(bytes8(zkOutput[end:end + 8]));
        if (checkedAt > block.timestamp || block.timestamp - checkedAt > maxAge) revert StaleProof(checkedAt);

        IDcapZkOutput quoteVerifier = IDcapQuoteVerifiers(address(dcap)).quoteVerifiers(uint16(bytes2(zkOutput[2:4])));
        if (address(quoteVerifier) == address(0)) revert UnsupportedReport();
        (bool genuine, bytes memory output) = quoteVerifier.verifyZkOutput(zkOutput, 0);
        if (!genuine) revert QuoteRejected(output);
        digest = _checkOutput(output);
        _approveConfigId(output, digest, zkOutput);
    }
}
