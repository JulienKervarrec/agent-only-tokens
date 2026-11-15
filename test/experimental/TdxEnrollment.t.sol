// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAgentRegistry} from "../../src/IAgentRegistry.sol";
import {AgentAccount} from "../../src/AgentAccount.sol";
import {AttestedAgentRegistry} from "../../src/AttestedAgentRegistry.sol";
import {IDcapAttestation, TdxQuoteVerifier} from "../../src/experimental/TdxQuoteVerifier.sol";
import {TdxEnrollmentVerifier} from "../../src/experimental/TdxEnrollmentVerifier.sol";
import {AgentOnlyBase, AnyCollection} from "../AgentOnly.t.sol";

/// Stands in for the DCAP verifier. It answers in the verifier's format, from the quote's own
/// report body, but checks no signature: the test decides whether the quote counts as genuine
/// and what the platform's security level is.
contract DcapStub is IDcapAttestation {
    bool public genuine = true;
    uint8 public tcbStatus;
    uint16 public bodyType = 2;

    function set(bool genuine_, uint8 tcbStatus_, uint16 bodyType_) external {
        (genuine, tcbStatus, bodyType) = (genuine_, tcbStatus_, bodyType_);
    }

    function verifyAndAttestOnChain(bytes calldata quote) external payable returns (bool, bytes memory) {
        if (!genuine) return (false, bytes("signature check failed"));
        // version, body type, security level, platform family, then the 584-byte report body.
        return (true, abi.encodePacked(uint16(4), bodyType, tcbStatus, bytes6(0), quote[48:632]));
    }
}

/// Enrollment by hardware attestation instead of attester signatures.
/// The quotes are built from a real Intel TDX quote (test/experimental/tdx/quote-v4.hex): the report body,
/// with its real measurements, is kept, and only the report data is replaced by the digest
/// under test. That breaks the quote's real signature, which the stub does not check.
contract TdxEnrollmentTest is AgentOnlyBase {
    // The report body starts after the quote's 48-byte header.
    uint256 constant BODY = 48;
    uint256 constant TD_ATTRIBUTES = BODY + 120;
    uint256 constant MR_TD = BODY + 136;
    uint256 constant RTMR3 = BODY + 472;
    uint256 constant REPORT_DATA = BODY + 520;
    // keccak256 of bytes 120 to 520 of the real quote's report body, computed outside Solidity.
    bytes32 constant REAL_CODE = 0x7dda0b4a87de3d2ad86eccd9d37cb9cc01bf17d97eb39abb2eabe2e8a1e81ce6;
    uint256 constant ENCLAVE_KEY = 0x7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d;

    DcapStub dcap;
    TdxEnrollmentVerifier verifier;
    AttestedAgentRegistry treg;
    AnyCollection tnft;
    bytes realQuote;

    function setUp() public override {
        super.setUp();
        realQuote = vm.parseBytes(vm.readFile("test/experimental/tdx/quote-v4.hex"));
        dcap = new DcapStub();
        bytes32[] memory approved = new bytes32[](1);
        approved[0] = REAL_CODE;
        verifier = new TdxEnrollmentVerifier(dcap, 1, approved); // up-to-date platforms only

        address[] memory att = new address[](3);
        (att[0], att[1], att[2]) = (vm.addr(A1), vm.addr(A2), vm.addr(A3));
        treg = new AttestedAgentRegistry(att, 2, BOND, TTL, IERC721(address(0)), address(verifier));
        tnft = new AnyCollection(IAgentRegistry(address(treg)));
    }

    // ------------------------------------------------------------ helpers

    function _quoteFor(bytes32 digest) internal view returns (bytes memory quote) {
        quote = realQuote;
        for (uint256 i; i < 32; ++i) {
            quote[REPORT_DATA + i] = digest[i];
        }
    }

    function _digest(address sponsor, uint256 agent, address key) internal view returns (bytes32) {
        return treg.hashEnrollment(agent, key, bytes32(0), sponsor, treg.enrollmentNonce(agent), FAR);
    }

    function _enrollWith(address sponsor, uint256 agent, address key, uint256 value, bytes[] memory sigs) internal {
        vm.prank(sponsor);
        treg.enroll{value: value}(agent, key, bytes32(0), FAR, sigs);
    }

    // ------------------------------------------------------------ the path that works

    function test_KeyAttestedByApprovedCodeEnrolls() public {
        address key = vm.addr(ENCLAVE_KEY);
        bytes32 digest = _digest(SPONSOR1, 7, key);

        // Anyone can carry the quote to the verifier.
        vm.prank(human);
        assertEq(verifier.attest(_quoteFor(digest)), digest);
        assertEq(verifier.isValidSignature(digest, ""), bytes4(0x1626ba7e));

        // No attester signature is needed.
        _enrollWith(SPONSOR1, 7, key, BOND, new bytes[](0));
        AgentAccount acc = AgentAccount(payable(treg.accountOf(7)));
        assertTrue(treg.isAgent(address(acc)));

        // The enrolled key drives a normal agent account.
        vm.prank(key);
        uint256 id = abi.decode(acc.execute(address(tnft), 0, abi.encodeCall(tnft.mint, (bytes32(0)))), (uint256));
        assertEq(tnft.ownerOf(id), address(acc));
    }

    function test_RealQuoteFieldsAreReadAtTheRightPlace() public {
        // The untouched real quote: its code identity matches the value computed outside
        // Solidity, it is not a debug machine, and its report data is empty.
        (, bytes memory output) = dcap.verifyAndAttestOnChain(realQuote);
        assertEq(verifier.codeOf(output), REAL_CODE);
        assertEq(verifier.attest(realQuote), bytes32(0));
    }

    // ------------------------------------------------------------ what is refused

    function test_NoQuoteNoEnrollment() public {
        address key = vm.addr(ENCLAVE_KEY);
        vm.expectRevert(AttestedAgentRegistry.NotVerified.selector);
        _enrollWith(SPONSOR1, 7, key, BOND, new bytes[](0));

        // Attester signatures do not replace the hardware proof.
        bytes[] memory sigs = _attest(A1, A2, _digest(SPONSOR1, 7, key));
        vm.expectRevert(AttestedAgentRegistry.NotVerified.selector);
        _enrollWith(SPONSOR1, 7, key, BOND, sigs);
    }

    function test_QuoteIsBoundToKeySponsorAndAgent() public {
        address key = vm.addr(ENCLAVE_KEY);
        verifier.attest(_quoteFor(_digest(SPONSOR1, 7, key)));

        // Another key (a human's), another sponsor, another agent id: all refused.
        vm.expectRevert(AttestedAgentRegistry.NotVerified.selector);
        _enrollWith(SPONSOR1, 7, human, BOND, new bytes[](0));
        vm.expectRevert(AttestedAgentRegistry.NotVerified.selector);
        _enrollWith(SPONSOR2, 7, key, BOND, new bytes[](0));
        vm.expectRevert(AttestedAgentRegistry.NotVerified.selector);
        _enrollWith(SPONSOR1, 8, key, BOND, new bytes[](0));
    }

    function test_QuoteCannotBeReusedForTheNextEnrollment() public {
        address key = vm.addr(ENCLAVE_KEY);
        verifier.attest(_quoteFor(_digest(SPONSOR1, 7, key)));
        _enrollWith(SPONSOR1, 7, key, BOND, new bytes[](0));

        // Renewing the same key needs a fresh quote: the digest changed with the nonce.
        vm.expectRevert(AttestedAgentRegistry.NotVerified.selector);
        _enrollWith(SPONSOR1, 7, key, 0, new bytes[](0));

        verifier.attest(_quoteFor(_digest(SPONSOR1, 7, key)));
        _enrollWith(SPONSOR1, 7, key, 0, new bytes[](0));
    }

    function test_RefusesQuoteTheVerifierRejects() public {
        dcap.set(false, 0, 2);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.QuoteRejected.selector, bytes("signature check failed")));
        verifier.attest(_quoteFor(keccak256("digest")));
    }

    function test_RefusesOtherCode() public {
        // One bit changed in the boot measurement, or in a runtime register.
        bytes memory quote = _quoteFor(keccak256("digest"));
        quote[MR_TD] ^= 0x01;
        vm.expectPartialRevert(TdxQuoteVerifier.UnknownCode.selector);
        verifier.attest(quote);

        quote = _quoteFor(keccak256("digest"));
        quote[RTMR3 + 47] ^= 0x01;
        vm.expectPartialRevert(TdxQuoteVerifier.UnknownCode.selector);
        verifier.attest(quote);
    }

    function test_RefusesDebugMachineEvenIfItsCodeWasApproved() public {
        bytes memory quote = _quoteFor(keccak256("digest"));
        quote[TD_ATTRIBUTES] = 0x01;
        (, bytes memory output) = dcap.verifyAndAttestOnChain(quote);
        bytes32[] memory approved = new bytes32[](1);
        approved[0] = verifier.codeOf(output);
        TdxEnrollmentVerifier careless = new TdxEnrollmentVerifier(dcap, 1, approved);

        vm.expectRevert(TdxQuoteVerifier.DebugMachine.selector);
        careless.attest(quote);
    }

    function test_RefusesPlatformBelowTheAcceptedLevel() public {
        bytes memory quote = _quoteFor(keccak256("digest"));
        for (uint8 status = 1; status < 8; ++status) {
            dcap.set(true, status, 2);
            vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.PlatformNotAccepted.selector, status));
            verifier.attest(quote);
        }
        // A level outside the known range is refused too, whatever was accepted at deployment.
        bytes32[] memory approved = new bytes32[](1);
        approved[0] = REAL_CODE;
        TdxEnrollmentVerifier lax = new TdxEnrollmentVerifier(dcap, 0xff, approved);
        dcap.set(true, 8, 2);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.PlatformNotAccepted.selector, uint8(8)));
        lax.attest(quote);
        // That lax deployment does accept an outdated platform: the choice is made at deployment.
        dcap.set(true, 4, 2);
        lax.attest(quote);
    }

    function test_RefusesReportsThatAreNotTdx10() public {
        bytes memory quote = _quoteFor(keccak256("digest"));
        dcap.set(true, 0, 1); // an SGX enclave report
        vm.expectRevert(TdxQuoteVerifier.UnsupportedReport.selector);
        verifier.attest(quote);
        dcap.set(true, 0, 3); // a TDX 1.5 report
        vm.expectRevert(TdxQuoteVerifier.UnsupportedReport.selector);
        verifier.attest(quote);
    }

    function test_RefusesReportDataLongerThanADigest() public {
        bytes memory quote = _quoteFor(keccak256("digest"));
        quote[REPORT_DATA + 63] = 0x01;
        vm.expectRevert(TdxQuoteVerifier.BadReportData.selector);
        verifier.attest(quote);
    }

    /// Found by the independent review: a DCAP verifier that refunds unused fee to its caller
    /// must not block attestations; the refund goes back to whoever paid.
    function test_FeeRefundGoesBackToThePayer() public {
        TdxEnrollmentVerifier v = new TdxEnrollmentVerifier(new RefundingDcap(), 1, _approvedReal());
        address payer = makeAddr("payer");
        vm.deal(payer, 10);
        vm.prank(payer);
        v.attest{value: 10}(_quoteFor(keccak256("digest")));
        assertEq(payer.balance, 9); // fee of 1 kept by the DCAP verifier
        assertEq(address(v).balance, 0);
    }

    function _approvedReal() internal pure returns (bytes32[] memory a) {
        a = new bytes32[](1);
        a[0] = REAL_CODE;
    }

    function test_RefusesEmptyConfiguration() public {
        bytes32[] memory none = new bytes32[](0);
        bytes32[] memory one = new bytes32[](1);
        vm.expectRevert(TdxQuoteVerifier.BadConfig.selector);
        new TdxEnrollmentVerifier(dcap, 1, none);
        vm.expectRevert(TdxQuoteVerifier.BadConfig.selector);
        new TdxEnrollmentVerifier(dcap, 0, one);
        vm.expectRevert(TdxQuoteVerifier.BadConfig.selector);
        new TdxEnrollmentVerifier(IDcapAttestation(address(0)), 1, one);
    }

    // ------------------------------------------------------------ attesters keep their other roles

    function test_AttestersStillApproveVenuesAndRevoke() public {
        address key = vm.addr(ENCLAVE_KEY);
        verifier.attest(_quoteFor(_digest(SPONSOR1, 7, key)));
        _enrollWith(SPONSOR1, 7, key, BOND, new bytes[](0));
        address account = treg.accountOf(7);

        treg.setVenue(address(swap), true, keccak256("code"), _attest(A1, A2, treg.hashVenue(address(swap), true, keccak256("code"))));
        assertTrue(treg.isVenue(address(swap)));

        // If a quote turns out to be forged, the attesters can still revoke the agent.
        treg.revoke(7, _attest(A1, A3, treg.hashRevocation(7)));
        assertFalse(treg.isAgent(account));
    }
}

/// A DCAP verifier that keeps a fee of 1 wei and refunds the rest to its caller.
contract RefundingDcap is IDcapAttestation {
    function verifyAndAttestOnChain(bytes calldata quote) external payable returns (bool, bytes memory) {
        if (msg.value > 1) {
            (bool ok,) = msg.sender.call{value: msg.value - 1}("");
            require(ok, "refund failed");
        }
        return (true, abi.encodePacked(uint16(4), uint16(2), uint8(0), bytes6(0), quote[48:632]));
    }
}
