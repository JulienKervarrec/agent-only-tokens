// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// Entrypoint of an on-chain verifier of Intel attestation quotes. This is the interface of
/// Automata DCAP Attestation (v1.1 and later), which checks the quote's signatures and
/// certificates up to Intel's root key and returns what the quote states.
interface IDcapAttestation {
    function verifyAndAttestOnChain(bytes calldata rawQuote)
        external
        payable
        returns (bool success, bytes memory output);
}

/// @title Enrollment verifier: the agent proves it runs approved code in an Intel TDX machine.
/// @notice Unaudited draft.
/// @dev The agent's program runs in a TDX confidential virtual machine. It creates its session
/// key there, computes the registry's enrollment digest for that key and asks the processor for
/// a quote carrying the digest. Anyone can submit the quote to `attest`. This contract then
/// approves the digest (ERC-1271), which lets the registry enroll that key and no other.
///
/// What is checked: the quote is genuine (by the DCAP verifier), the platform's security level
/// is one of those accepted at deployment, the machine is not in debug mode, and the code it
/// booted is on the list fixed at deployment.
/// What is trusted: Intel, the DCAP verifier and its data, and the approved code itself, which
/// must request quotes only for enrollment digests of keys it created and never reveals.
contract TdxEnrollmentVerifier is IERC1271 {
    // Layout of the DCAP verifier's output: version (2 bytes), body type (2), security level (1),
    // platform family (6), then the report body as signed by the processor.
    uint256 private constant BODY = 11;
    uint256 private constant TD10_BODY_LENGTH = 584;
    uint16 private constant TD10_BODY_TYPE = 2;
    // Offsets inside the TDX 1.0 report body.
    uint256 private constant TD_ATTRIBUTES = 120; // 8 bytes; the first one holds the debug flags
    uint256 private constant MEASURED = 120; // attributes, features, boot measurements, owner
    uint256 private constant MEASURED_LENGTH = 400; // fields and the four runtime registers
    uint256 private constant REPORT_DATA = 520; // 64 bytes chosen by the program in the machine

    IDcapAttestation public immutable dcap;
    /// Accepted platform security levels, one bit per level as numbered by the DCAP verifier
    /// (bit 0: up to date). Fixed at deployment.
    uint8 public immutable acceptedTcb;

    /// Approved agent code, as the hash of everything the processor measured at boot. Fixed.
    mapping(bytes32 => bool) public isApprovedCode;
    /// Digests carried by a verified quote from approved code.
    mapping(bytes32 => bool) public attested;

    event Attested(bytes32 indexed digest, bytes32 indexed code, bytes32 quoteHash);

    error BadConfig();
    error QuoteRejected(bytes reason);
    error UnsupportedReport();
    error PlatformNotAccepted(uint8 tcbStatus);
    error DebugMachine();
    error UnknownCode(bytes32 code);
    error BadReportData();

    constructor(IDcapAttestation dcap_, uint8 acceptedTcb_, bytes32[] memory approvedCode) {
        if (address(dcap_) == address(0) || acceptedTcb_ == 0 || approvedCode.length == 0) revert BadConfig();
        dcap = dcap_;
        acceptedTcb = acceptedTcb_;
        for (uint256 i; i < approvedCode.length; ++i) {
            isApprovedCode[approvedCode[i]] = true;
        }
    }

    /// Verifies a quote and approves the digest it carries. Any fee asked by the DCAP verifier
    /// is forwarded; it returns what it does not use to the transaction's sender.
    function attest(bytes calldata quote) external payable returns (bytes32 digest) {
        (bool genuine, bytes memory output) = dcap.verifyAndAttestOnChain{value: msg.value}(quote);
        if (!genuine) revert QuoteRejected(output);
        if (output.length < BODY + TD10_BODY_LENGTH || uint16(bytes2(_word(output, 2))) != TD10_BODY_TYPE) {
            revert UnsupportedReport();
        }
        uint8 tcbStatus = uint8(output[4]);
        if ((acceptedTcb >> tcbStatus) & 1 == 0) revert PlatformNotAccepted(tcbStatus);
        // In debug mode the host can read the machine's memory, hence the key.
        if (output[BODY + TD_ATTRIBUTES] != 0) revert DebugMachine();

        bytes32 code = codeOf(output);
        if (!isApprovedCode[code]) revert UnknownCode(code);

        // The digest fills the first half of the report data; the second half stays empty.
        digest = _word(output, BODY + REPORT_DATA);
        if (_word(output, BODY + REPORT_DATA + 32) != 0) revert BadReportData();

        attested[digest] = true;
        emit Attested(digest, code, keccak256(quote));
    }

    /// ERC-1271: this contract "signs" exactly the digests carried by a verified quote.
    function isValidSignature(bytes32 hash, bytes calldata) external view returns (bytes4) {
        return attested[hash] ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }

    /// The identity of the code in a verified output: hash of the machine's attributes and
    /// enabled features, its boot measurement, its owner fields and its four runtime registers.
    function codeOf(bytes memory output) public pure returns (bytes32 code) {
        if (output.length < BODY + TD10_BODY_LENGTH) revert UnsupportedReport();
        uint256 start = BODY + MEASURED;
        assembly ("memory-safe") {
            code := keccak256(add(add(output, 0x20), start), MEASURED_LENGTH)
        }
    }

    function _word(bytes memory data, uint256 offset) private pure returns (bytes32 word) {
        assembly ("memory-safe") {
            word := mload(add(add(data, 0x20), offset))
        }
    }
}
