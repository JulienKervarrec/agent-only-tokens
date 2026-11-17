// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAgentRegistry} from "../../src/IAgentRegistry.sol";
import {AgentAccount} from "../../src/AgentAccount.sol";
import {AttestedAgentRegistry} from "../../src/AttestedAgentRegistry.sol";
import {TdxQuoteVerifier} from "../../src/experimental/TdxQuoteVerifier.sol";
import {DstackConfigIdVerifier} from "../../src/experimental/DstackConfigIdVerifier.sol";
import {DstackEnrollmentVerifier} from "../../src/experimental/DstackEnrollmentVerifier.sol";
import {AgentOnlyBase, AnyCollection} from "../AgentOnly.t.sol";
import {DcapStub} from "./TdxEnrollment.t.sol";

/// The verifier that reads the code identity from MRCONFIGID, on three real quotes from one
/// production dstack machine and one from another machine (test/experimental/phala). A stand-in
/// replaces the DCAP verifier; test/fork runs two of the quotes through the real one.
contract DstackConfigIdTest is AgentOnlyBase {
    uint256 constant BODY = 48; // the report body starts after the quote's header
    uint256 constant TD_ATTRIBUTES = BODY + 120;
    uint256 constant MR_CONFIG_ID = BODY + 184;
    uint256 constant RTMR1 = BODY + 376;
    uint256 constant RTMR3 = BODY + 472;
    uint256 constant REPORT_DATA = BODY + 520;
    bytes32 constant COMPOSE = 0x95b3c3e50b054db593842d68401d342d36136cd7c6002ecedebcdece9608dc21;
    bytes32 constant MODIFIED_COMPOSE = 0x6b79fe2460f3f6464dba5093077a0f0d0d6439e5087f37fd8fbd0097c6271412;
    // The digest the first real quote carries, and the key the machine created.
    bytes32 constant REAL_DIGEST = 0x6b8374eb8ae21bf4744c04bf503a96b5e6ce48eba2a8fb671fa6481293f9f631;
    // The second program (examples/enclave-agent/v2): its compose hash, the identity computed for
    // it before its machine existed, and the digest its first quote carries.
    bytes32 constant V2_COMPOSE = 0x580353bba6700abc63f66733f8b8449afc130eaffaed93153728faa7e8547ef8;
    bytes32 constant V2_CODE = 0x4b20b334ade6c2ee3c6fa18a95edb4d037506b747fe79343d004a3c8e9b472fc;
    bytes32 constant V2_DIGEST = 0x6d6d84cf892cd35cea63ce53c8acf809497daaf1282ce1970b0044456a52296f;
    uint256 constant ENCLAVE_KEY = 0x7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d;

    DcapStub dcap;
    DstackConfigIdVerifier verifier;
    bytes quote;
    bytes rotation;
    bytes modified;
    bytes32 code;

    function setUp() public override {
        super.setUp();
        quote = vm.parseBytes(vm.readFile("test/experimental/phala/quote.hex"));
        rotation = vm.parseBytes(vm.readFile("test/experimental/phala/quote-rotation.hex"));
        modified = vm.parseBytes(vm.readFile("test/experimental/phala/quote-modified.hex"));
        dcap = new DcapStub();
        code = _codeOf(quote);
        verifier = _verifier(code);
    }

    function _verifier(bytes32 approved) internal returns (DstackConfigIdVerifier) {
        bytes32[] memory list = new bytes32[](1);
        list[0] = approved;
        return new DstackConfigIdVerifier(dcap, 1, list); // up-to-date platforms only
    }

    /// keccak256 of attributes .. RTMR2 of a quote's report body.
    function _codeOf(bytes memory q) internal pure returns (bytes32 h) {
        assembly ("memory-safe") {
            h := keccak256(add(add(q, 0x20), 168), 352)
        }
    }

    function _with(bytes memory q, uint256 at, bytes1 value) internal pure returns (bytes memory out) {
        out = bytes.concat(q);
        out[at] = value;
    }

    // ------------------------------------------------------------ the real quotes

    function test_RealQuoteIsAcceptedAndItsCodeReadFromConfigId() public {
        (, bytes memory output) = dcap.verifyAndAttestOnChain(quote);
        assertEq(verifier.codeOf(output), code);
        assertEq(verifier.composeHashOf(output), COMPOSE);
        vm.expectEmit(address(verifier));
        emit TdxQuoteVerifier.Attested(REAL_DIGEST, code, keccak256(quote));
        assertEq(verifier.attest(quote), REAL_DIGEST);
        assertTrue(verifier.attested(REAL_DIGEST));
    }

    function test_SameBuildAfterRestartHasTheSameCode() public {
        assertEq(_codeOf(rotation), code);
        bytes32 digest = verifier.attest(rotation);
        assertTrue(digest != REAL_DIGEST && verifier.attested(digest));
    }

    function test_ModifiedBuildIsRefused() public {
        (, bytes memory output) = dcap.verifyAndAttestOnChain(modified);
        assertEq(verifier.composeHashOf(output), MODIFIED_COMPOSE);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.UnknownCode.selector, _codeOf(modified)));
        verifier.attest(modified);
    }

    /// The second program ran later, on another machine of the same provider. Its identity had
    /// been computed from the first machine's quote, by changing the compose hash only.
    function test_IdentityComputedBeforehandMatchesAnotherMachine() public {
        bytes memory other = vm.parseBytes(vm.readFile("test/experimental/phala/quote-other-machine.hex"));
        bytes memory predicted = bytes.concat(quote);
        for (uint256 i; i < 32; ++i) {
            predicted[MR_CONFIG_ID + 1 + i] = V2_COMPOSE[i];
        }
        assertEq(_codeOf(predicted), V2_CODE);
        assertEq(_codeOf(other), V2_CODE);

        DstackConfigIdVerifier second = _verifier(V2_CODE);
        assertEq(second.attest(other), V2_DIGEST);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.UnknownCode.selector, code));
        second.attest(quote);
    }

    function test_AnotherInstanceIsAccepted() public {
        // RTMR3 holds the instance id and the application's own events: it is not read.
        bytes memory other = _with(quote, RTMR3, quote[RTMR3] ^ 0x01);
        assertEq(verifier.attest(other), REAL_DIGEST);
    }

    function test_OtherBaseImageIsRefused() public {
        bytes memory other = _with(quote, RTMR1, quote[RTMR1] ^ 0x01);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.UnknownCode.selector, _codeOf(other)));
        verifier.attest(other);
    }

    function test_UnsetOrUndefinedConfigIdFormatsAreRefusedEvenIfApproved() public {
        // Format 0 is "unset", which dstack tolerates without checking anything; dstack defines
        // formats 1 to 3 only, and its OS refuses to boot on any other.
        uint8[4] memory formats = [0, 4, 0x80, 0xff];
        for (uint256 i; i < formats.length; ++i) {
            bytes memory q = _with(quote, MR_CONFIG_ID, bytes1(formats[i]));
            DstackConfigIdVerifier lax = _verifier(_codeOf(q));
            vm.expectRevert(DstackConfigIdVerifier.BadConfigId.selector);
            lax.attest(q);
        }
        bytes memory unset = bytes.concat(quote);
        for (uint256 i; i < 48; ++i) {
            unset[MR_CONFIG_ID + i] = 0;
        }
        DstackConfigIdVerifier anyCode = _verifier(_codeOf(unset));
        vm.expectRevert(DstackConfigIdVerifier.BadConfigId.selector);
        anyCode.attest(unset);
    }

    // ------------------------------------------------------------ formats 2 and 3

    // The machine of 17 November 2026 (examples/enclave-agent/run-2026-11-17-prelaunch): its
    // compose hash, and from its RTMR3 events its application id, instance id and the public key
    // of its KMS. dstack wrote format 1; formats 2 and 3 are what it would have written if the
    // manifest had pinned the key provider (dstack-types/src/mr_config.rs).
    bytes32 constant RUN_COMPOSE = 0x024261d8dbc43aef02147dc1790aae23d75e2bde92ddf899b294d3913f9e39b5;
    bytes20 constant RUN_APP_ID = bytes20(hex"39f1081414996bf4d10a9c879f8cd3b348f93f2a");
    bytes constant RUN_KMS_ID =
        hex"3059301306072a8648ce3d020106082a8648ce3d03010703420004e8e325a477b0bf22800dc927a46c68638938d283fe73d1f9028eeac7028193f3470122193875f598b7addc503e534712ab437b4120776bbac32ddf8897f844ee";
    string constant RUN_V3_DOCUMENT = '{"app_id":"39f1081414996bf4d10a9c879f8cd3b348f93f2a",'
        '"compose_hash":"024261d8dbc43aef02147dc1790aae23d75e2bde92ddf899b294d3913f9e39b5",'
        '"instance_id":"10027d4ddad47be7f3342784eb3bceb10a847b61",' '"key_provider":"kms",'
        '"key_provider_id":"3059301306072a8648ce3d020106082a8648ce3d03010703420004e8e325a477b0bf22800dc927a46c68638938d283fe73d1f9028eeac7028193f3470122193875f598b7addc503e534712ab437b4120776bbac32ddf8897f844ee",'
        '"version":3}';

    function _withConfigId(bytes memory q, uint8 format, bytes32 value) internal pure returns (bytes memory out) {
        out = bytes.concat(q);
        out[MR_CONFIG_ID] = bytes1(format);
        for (uint256 i; i < 32; ++i) {
            out[MR_CONFIG_ID + 1 + i] = value[i];
        }
    }

    function test_FormatsTwoAndThreeAreAcceptedOnlyAsApproved() public {
        bytes memory run = vm.parseBytes(vm.readFile("test/experimental/phala/quote-own-prelaunch.hex"));
        assertEq(run[MR_CONFIG_ID], bytes1(0x01));
        assertEq(_word(run, MR_CONFIG_ID + 1), RUN_COMPOSE);

        bytes32 v2 = keccak256(abi.encodePacked(RUN_COMPOSE, RUN_APP_ID, uint8(2), RUN_KMS_ID)); // 2: KMS
        bytes32 v3 = sha256(abi.encodePacked("dstack-mr-config-v3:", bytes1(0), RUN_V3_DOCUMENT));
        bytes[3] memory forms = [run, _withConfigId(run, 2, v2), _withConfigId(run, 3, v3)];

        for (uint256 i; i < 3; ++i) {
            // Each form is accepted by a verifier that approves it, and by no other.
            DstackConfigIdVerifier approving = _verifier(_codeOf(forms[i]));
            assertEq(approving.attest(forms[i]), _word(forms[i], REPORT_DATA));
            for (uint256 j; j < 3; ++j) {
                if (j == i) continue;
                vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.UnknownCode.selector, _codeOf(forms[j])));
                approving.attest(forms[j]);
            }
        }

        // The compose hash is read in format 1 only: the others carry a hash of it.
        (, bytes memory output) = dcap.verifyAndAttestOnChain(forms[0]);
        assertEq(verifier.composeHashOf(output), RUN_COMPOSE);
        for (uint256 i = 1; i < 3; ++i) {
            (, output) = dcap.verifyAndAttestOnChain(forms[i]);
            vm.expectRevert(DstackConfigIdVerifier.BadConfigId.selector);
            verifier.composeHashOf(output);
        }
    }

    function _word(bytes memory b, uint256 at) internal pure returns (bytes32 w) {
        assembly ("memory-safe") {
            w := mload(add(add(b, 0x20), at))
        }
    }

    function test_SharedChecksStillApply() public {
        bytes memory debug = _with(quote, TD_ATTRIBUTES, 0x01);
        DstackConfigIdVerifier lax = _verifier(_codeOf(debug));
        vm.expectRevert(TdxQuoteVerifier.DebugMachine.selector);
        lax.attest(debug);

        vm.expectRevert(TdxQuoteVerifier.BadReportData.selector);
        verifier.attest(_with(quote, REPORT_DATA + 40, 0x01));

        dcap.set(true, 4, 2);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.PlatformNotAccepted.selector, uint8(4)));
        verifier.attest(quote);

        dcap.set(false, 0, 2);
        vm.expectRevert(
            abi.encodeWithSelector(TdxQuoteVerifier.QuoteRejected.selector, bytes("signature check failed"))
        );
        verifier.attest(quote);
    }

    function test_RefusesEmptyConfiguration() public {
        vm.expectRevert(TdxQuoteVerifier.BadConfig.selector);
        new DstackConfigIdVerifier(dcap, 1, new bytes32[](0));
    }

    function test_ReadsNothingFromATruncatedOutput() public {
        vm.expectRevert(TdxQuoteVerifier.UnsupportedReport.selector);
        verifier.composeHashOf(new bytes(594));
        vm.expectRevert(TdxQuoteVerifier.UnsupportedReport.selector);
        verifier.codeOf(new bytes(594));
    }

    // ------------------------------------------------------------ end to end

    function test_AgentEnrollsThroughTheConfigIdAndActs() public {
        address[] memory att = new address[](3);
        (att[0], att[1], att[2]) = (vm.addr(A1), vm.addr(A2), vm.addr(A3));
        AttestedAgentRegistry treg =
            new AttestedAgentRegistry(att, 2, BOND, TTL, NOTICE, IERC721(address(0)), address(verifier));
        AnyCollection tnft = new AnyCollection(IAgentRegistry(address(treg)));
        address key = vm.addr(ENCLAVE_KEY);
        bytes32 digest = treg.hashEnrollment(9, key, COMPOSE, SPONSOR1, 0, FAR);

        // No quote yet: refused. Then the quote carrying that digest, and the enrollment passes.
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.NotVerified.selector);
        treg.enroll{value: BOND}(9, key, COMPOSE, FAR, new bytes[](0));

        bytes memory q = bytes.concat(quote);
        for (uint256 i; i < 32; ++i) {
            q[REPORT_DATA + i] = digest[i];
        }
        verifier.attest(q);
        vm.prank(SPONSOR1);
        treg.enroll{value: BOND}(9, key, COMPOSE, FAR, new bytes[](0));

        AgentAccount acc = AgentAccount(payable(treg.accountOf(9)));
        vm.prank(key);
        acc.execute(address(tnft), 0, abi.encodeCall(tnft.mint, (bytes32(uint256(1)))));
        assertEq(tnft.ownerOf(1), address(acc));
    }

    // ------------------------------------------------------------ upgrading the program

    function _quoteFor(bytes memory base, bytes32 digest) internal pure returns (bytes memory q) {
        q = bytes.concat(base);
        for (uint256 i; i < 32; ++i) {
            q[REPORT_DATA + i] = digest[i];
        }
    }

    function _registry(address enrollmentVerifier) internal returns (AttestedAgentRegistry) {
        address[] memory att = new address[](3);
        (att[0], att[1], att[2]) = (vm.addr(A1), vm.addr(A2), vm.addr(A3));
        return new AttestedAgentRegistry(att, 2, BOND, TTL, NOTICE, IERC721(address(0)), enrollmentVerifier);
    }

    function _replace(AttestedAgentRegistry r, address next) internal {
        bytes32 digest = r.hashVerifier(next, keccak256("review"), FAR);
        r.setEnrollmentVerifier(next, keccak256("review"), FAR, _attest(A1, A2, digest));
    }

    /// The agents' program changes from the first build to the second one. The attesters replace
    /// the verifier; the agent keeps its id, its account and its token.
    function test_ProgramUpgradeKeepsTheAccountAndItsTokens() public {
        bytes memory other = vm.parseBytes(vm.readFile("test/experimental/phala/quote-other-machine.hex"));
        AttestedAgentRegistry treg = _registry(address(verifier));
        AnyCollection tnft = new AnyCollection(IAgentRegistry(address(treg)));
        DstackConfigIdVerifier second = _verifier(V2_CODE);
        address key = vm.addr(ENCLAVE_KEY);
        address nextKey = vm.addr(ENCLAVE_KEY + 1);

        verifier.attest(_quoteFor(quote, treg.hashEnrollment(9, key, COMPOSE, SPONSOR1, 0, FAR)));
        vm.prank(SPONSOR1);
        treg.enroll{value: BOND}(9, key, COMPOSE, FAR, new bytes[](0));
        AgentAccount acc = AgentAccount(payable(treg.accountOf(9)));
        vm.prank(key);
        acc.execute(address(tnft), 0, abi.encodeCall(tnft.mint, (bytes32(uint256(1)))));

        // The second build asks for a key before the attesters have decided: refused.
        second.attest(_quoteFor(other, treg.hashEnrollment(9, nextKey, V2_COMPOSE, SPONSOR1, 1, FAR)));
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.NotVerified.selector);
        treg.enroll(9, nextKey, V2_COMPOSE, FAR, new bytes[](0));

        vm.expectEmit(address(treg));
        emit AttestedAgentRegistry.EnrollmentVerifierSet(
            address(second), keccak256("review"), uint64(block.timestamp) + NOTICE
        );
        _replace(treg, address(second));

        // The decision is announced, not yet in force: the second build is still refused.
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.NotVerified.selector);
        treg.enroll(9, nextKey, V2_COMPOSE, FAR, new bytes[](0));
        skip(NOTICE);

        // The key enrolled under the first build still works until it is replaced or expires.
        vm.prank(key);
        acc.execute(address(tnft), 0, abi.encodeCall(tnft.mint, (bytes32(uint256(2)))));
        // The first build can no longer obtain a key.
        verifier.attest(_quoteFor(quote, treg.hashEnrollment(9, key, COMPOSE, SPONSOR1, 1, FAR)));
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.NotVerified.selector);
        treg.enroll(9, key, COMPOSE, FAR, new bytes[](0));

        vm.prank(SPONSOR1);
        treg.enroll(9, nextKey, V2_COMPOSE, FAR, new bytes[](0));
        assertEq(treg.accountOf(9), address(acc));
        vm.prank(key);
        vm.expectRevert(AgentAccount.NotKey.selector);
        acc.execute(address(tnft), 0, abi.encodeCall(tnft.mint, (bytes32(uint256(3)))));
        vm.prank(nextKey);
        acc.execute(address(tnft), 0, abi.encodeCall(tnft.mint, (bytes32(uint256(3)))));
        assertEq(tnft.balanceOf(address(acc)), 3);
        assertEq(tnft.ownerOf(1), address(acc));
    }

    function test_OnlyTheAttestersReplaceTheVerifier() public {
        AttestedAgentRegistry treg = _registry(address(verifier));
        address next = address(_verifier(V2_CODE));
        bytes32 digest = treg.hashVerifier(next, keccak256("review"), FAR);
        bytes[] memory one = new bytes[](1);
        one[0] = _sign(A1, digest);
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        treg.setEnrollmentVerifier(next, keccak256("review"), FAR, one);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        treg.setEnrollmentVerifier(next, keccak256("review"), FAR, _attest(A1, HUMAN_PK, digest));
        // Signatures given for one verifier do not install another one, nor another evidence,
        // and do not last longer than the attesters said.
        bytes[] memory sigs = _attest(A1, A2, digest);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        treg.setEnrollmentVerifier(address(verifier), keccak256("review"), FAR, sigs);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        treg.setEnrollmentVerifier(next, keccak256("other"), FAR, sigs);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        treg.setEnrollmentVerifier(next, keccak256("review"), FAR + 1, sigs);

        treg.setEnrollmentVerifier(next, keccak256("review"), FAR, sigs);
        assertEq(treg.enrollmentVerifier(), address(verifier));
        skip(NOTICE);
        assertEq(treg.enrollmentVerifier(), next);
        // The attesters go back to the first verifier; the earlier decision cannot be replayed.
        _replace(treg, address(verifier));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        treg.setEnrollmentVerifier(next, keccak256("review"), FAR, sigs);
        skip(NOTICE);
        assertEq(treg.enrollmentVerifier(), address(verifier));
    }

    function test_DeploymentAnnouncesItsVerifier() public {
        vm.expectEmit();
        emit AttestedAgentRegistry.EnrollmentVerifierSet(address(verifier), bytes32(0), uint64(block.timestamp));
        _registry(address(verifier));
    }

    function test_WithoutVerifierEnrollmentsAreSignedAgain() public {
        AttestedAgentRegistry treg = _registry(address(verifier));
        _replace(treg, address(0));
        skip(NOTICE);
        address key = vm.addr(ENCLAVE_KEY);
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        treg.enroll{value: BOND}(9, key, COMPOSE, FAR, new bytes[](0));
        _enroll(treg, SPONSOR1, 9, key, BOND);
        assertEq(treg.keyOf(9), key);
    }

    /// The event-log verifier accepts the same production quote, with its ten real events.
    function test_EventLogVerifierAcceptsTheSameQuote() public {
        bytes memory events = vm.parseBytes(vm.readFile("test/experimental/phala/event-digests.hex"));
        (, bytes memory output) = dcap.verifyAndAttestOnChain(quote);
        bytes32[] memory list = new bytes32[](1);
        DstackEnrollmentVerifier probe = new DstackEnrollmentVerifier(dcap, 1, new bytes32[](1));
        list[0] = probe.codeOf(output, COMPOSE);
        DstackEnrollmentVerifier logVerifier = new DstackEnrollmentVerifier(dcap, 1, list);
        assertEq(logVerifier.attest(quote, events, 2, false, COMPOSE), REAL_DIGEST);
        // The modified build cannot pass with the approved build's log.
        vm.expectRevert(DstackEnrollmentVerifier.BadEventLog.selector);
        logVerifier.attest(modified, events, 2, false, COMPOSE);
    }

    function test_GasOfBothRoutes() public {
        bytes memory events = vm.parseBytes(vm.readFile("test/experimental/phala/event-digests.hex"));
        (, bytes memory output) = dcap.verifyAndAttestOnChain(quote);
        bytes32[] memory list = new bytes32[](1);
        list[0] = new DstackEnrollmentVerifier(dcap, 1, new bytes32[](1)).codeOf(output, COMPOSE);
        DstackEnrollmentVerifier logVerifier = new DstackEnrollmentVerifier(dcap, 1, list);
        uint256 g = gasleft();
        verifier.attest(quote);
        emit log_named_uint("attest by config id, without the DCAP verification", g - gasleft());
        g = gasleft();
        logVerifier.attest(quote, events, 2, false, COMPOSE);
        emit log_named_uint("attest by event log (10 events), without the DCAP verification", g - gasleft());
    }
}
