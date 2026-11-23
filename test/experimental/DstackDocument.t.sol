// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TdxQuoteVerifier} from "../../src/experimental/TdxQuoteVerifier.sol";
import {DstackDocumentVerifier} from "../../src/experimental/DstackDocumentVerifier.sol";
import {DcapStub} from "./TdxEnrollment.t.sol";

/// The verifier for MRCONFIGID in format 3, on the real quote of a machine with dstack OS 0.6.4
/// (test/experimental/phala/os064-quote.hex, 23 November 2026). A stand-in replaces the DCAP
/// verifier; test/fork runs the quote through the real one.
contract DstackDocumentTest is Test {
    uint256 constant BODY = 48; // the report body starts after the quote's header
    uint256 constant MR_CONFIG_ID = BODY + 184;
    uint256 constant RTMR1 = BODY + 376;
    uint256 constant RTMR3 = BODY + 472;
    // What Phala Cloud and the machine's event log showed for that machine.
    bytes20 constant APP = hex"7304267bd32e1b49e6efa19ab73a756ee30c14e7";
    bytes20 constant INSTANCE = hex"b3416d34c3cc2fbb760d38767ce6094807161e5b";
    bytes32 constant COMPOSE = 0x66dfe96ab4493d8f81c21567f409b4bca40502907adf9f5472196d503a34b513;
    bytes constant KEY_PROVIDER =
        hex"3059301306072a8648ce3d020106082a8648ce3d03010703420004e8e325a477b0bf22800dc927a46c68638938d283fe73d1f9028eeac7028193f3470122193875f598b7addc503e534712ab437b4120776bbac32ddf8897f844ee";
    // The enrollment digest the quote carries.
    bytes32 constant DIGEST = 0xc76134bb92174ec024c80b421d70b56dac0393e9b4e66914dc1e1ac2fa1c81ce;

    DcapStub dcap;
    DstackDocumentVerifier verifier;
    bytes quote;
    bytes32 program;

    function setUp() public {
        quote = vm.parseBytes(vm.readFile("test/experimental/phala/os064-quote.hex"));
        dcap = new DcapStub();
        // A first verifier only to compute the identity; the list is fixed at deployment.
        DstackDocumentVerifier probe = _verifier(bytes32(uint256(1)));
        (, bytes memory output) = dcap.verifyAndAttestOnChain(quote);
        program = probe.programOf(probe.imageOf(output), COMPOSE, KEY_PROVIDER);
        verifier = _verifier(program);
    }

    function _verifier(bytes32 approved) internal returns (DstackDocumentVerifier) {
        bytes32[] memory list = new bytes32[](1);
        list[0] = approved;
        return new DstackDocumentVerifier(dcap, 1, list); // up-to-date platforms only
    }

    function _with(bytes memory q, uint256 at, bytes memory value) internal pure returns (bytes memory out) {
        out = bytes.concat(q);
        for (uint256 i; i < value.length; ++i) {
            out[at + i] = value[i];
        }
    }

    // ------------------------------------------------------------ the real quote

    function test_DocumentIsTheOnePhalaCloudWrote() public view {
        assertEq(
            string(verifier.documentOf(APP, INSTANCE, COMPOSE, KEY_PROVIDER)),
            '{"app_id":"7304267bd32e1b49e6efa19ab73a756ee30c14e7","compose_hash":"66dfe96ab4493d8f81c21567f409b4bca40502907adf9f5472196d503a34b513","init_script_hashes":[],"instance_id":"b3416d34c3cc2fbb760d38767ce6094807161e5b","key_provider":"kms","key_provider_id":"3059301306072a8648ce3d020106082a8648ce3d03010703420004e8e325a477b0bf22800dc927a46c68638938d283fe73d1f9028eeac7028193f3470122193875f598b7addc503e534712ab437b4120776bbac32ddf8897f844ee","version":3}'
        );
        // The field of the real quote.
        assertEq(
            verifier.configIdOf(APP, INSTANCE, COMPOSE, KEY_PROVIDER),
            hex"030a2872d7caef138cec80c3e49f6cbd6abe95994a00ce1e624bd1066e42430147000000000000000000000000000000"
        );
    }

    function test_RealQuoteIsAccepted() public {
        vm.expectEmit(address(verifier));
        emit TdxQuoteVerifier.Attested(DIGEST, program, keccak256(quote));
        assertEq(verifier.attest(quote, APP, INSTANCE, COMPOSE, KEY_PROVIDER), DIGEST);
        assertTrue(verifier.attested(DIGEST));
    }

    function test_WrongFieldsOfTheDocumentAreRefused() public {
        vm.expectRevert(DstackDocumentVerifier.BadConfigId.selector);
        verifier.attest(quote, bytes20(uint160(APP) ^ 1), INSTANCE, COMPOSE, KEY_PROVIDER);
        vm.expectRevert(DstackDocumentVerifier.BadConfigId.selector);
        verifier.attest(quote, APP, bytes20(uint160(INSTANCE) ^ 1), COMPOSE, KEY_PROVIDER);
        vm.expectRevert(DstackDocumentVerifier.BadConfigId.selector);
        verifier.attest(quote, APP, INSTANCE, COMPOSE ^ bytes32(uint256(1)), KEY_PROVIDER);
        vm.expectRevert(DstackDocumentVerifier.BadConfigId.selector);
        verifier.attest(quote, APP, INSTANCE, COMPOSE, bytes.concat(KEY_PROVIDER, hex"00"));
        vm.expectRevert(DstackDocumentVerifier.BadConfigId.selector);
        verifier.attest(quote, APP, INSTANCE, COMPOSE, "");
    }

    // ------------------------------------------------------------ what the approval covers

    /// The point of this verifier: another machine of the same program, with its own application
    /// and instance ids, needs no new approval.
    function testFuzz_AnotherMachineOfTheSameProgramIsAccepted(bytes20 app, bytes20 instance) public {
        bytes memory other = _with(quote, MR_CONFIG_ID, verifier.configIdOf(app, instance, COMPOSE, KEY_PROVIDER));
        assertEq(verifier.attest(other, app, instance, COMPOSE, KEY_PROVIDER), DIGEST);
    }

    function test_AnotherProgramIsRefused() public {
        bytes32 otherCompose = keccak256("another compose file");
        bytes memory other = _with(quote, MR_CONFIG_ID, verifier.configIdOf(APP, INSTANCE, otherCompose, KEY_PROVIDER));
        (, bytes memory output) = dcap.verifyAndAttestOnChain(other);
        bytes32 code = verifier.programOf(verifier.imageOf(output), otherCompose, KEY_PROVIDER);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.UnknownCode.selector, code));
        verifier.attest(other, APP, INSTANCE, otherCompose, KEY_PROVIDER);
    }

    function test_AnotherKeyProviderIsRefused() public {
        bytes memory otherProvider = bytes.concat(KEY_PROVIDER);
        otherProvider[90] ^= 0x01;
        bytes memory other = _with(quote, MR_CONFIG_ID, verifier.configIdOf(APP, INSTANCE, COMPOSE, otherProvider));
        (, bytes memory output) = dcap.verifyAndAttestOnChain(other);
        bytes32 code = verifier.programOf(verifier.imageOf(output), COMPOSE, otherProvider);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.UnknownCode.selector, code));
        verifier.attest(other, APP, INSTANCE, COMPOSE, otherProvider);
    }

    function test_AnotherBaseImageIsRefused() public {
        bytes memory other = bytes.concat(quote);
        other[RTMR1] ^= 0x01;
        (, bytes memory output) = dcap.verifyAndAttestOnChain(other);
        bytes32 code = verifier.programOf(verifier.imageOf(output), COMPOSE, KEY_PROVIDER);
        assertTrue(code != program);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.UnknownCode.selector, code));
        verifier.attest(other, APP, INSTANCE, COMPOSE, KEY_PROVIDER);
    }

    /// Every byte the processor measured at boot, MRCONFIGID aside, is in the image.
    function testFuzz_AnyMeasuredByteChangesTheImage(uint256 at, uint8 flip) public {
        at = bound(at, 120, 471);
        vm.assume(at < 184 || at >= 232);
        flip = uint8(bound(flip, 1, 255));
        (, bytes memory output) = dcap.verifyAndAttestOnChain(quote);
        bytes32 image = verifier.imageOf(output);
        output[11 + at] ^= bytes1(flip);
        assertTrue(verifier.imageOf(output) != image);
    }

    function test_Rtmr3IsNotRead() public {
        bytes memory other = bytes.concat(quote);
        other[RTMR3] ^= 0x01;
        assertEq(verifier.attest(other, APP, INSTANCE, COMPOSE, KEY_PROVIDER), DIGEST);
    }

    // ------------------------------------------------------------ other shapes of the field

    function test_OtherFormatsAndPaddingAreRefused() public {
        bytes memory field = verifier.configIdOf(APP, INSTANCE, COMPOSE, KEY_PROVIDER);
        for (uint8 format; format < 5; ++format) {
            if (format == 3) continue;
            field[0] = bytes1(format);
            vm.expectRevert(DstackDocumentVerifier.BadConfigId.selector);
            verifier.attest(_with(quote, MR_CONFIG_ID, field), APP, INSTANCE, COMPOSE, KEY_PROVIDER);
        }
        field[0] = 0x03;
        field[47] = 0x01;
        vm.expectRevert(DstackDocumentVerifier.BadConfigId.selector);
        verifier.attest(_with(quote, MR_CONFIG_ID, field), APP, INSTANCE, COMPOSE, KEY_PROVIDER);
        // A field left unset, which dstack tolerates without checking anything.
        vm.expectRevert(DstackDocumentVerifier.BadConfigId.selector);
        verifier.attest(_with(quote, MR_CONFIG_ID, new bytes(48)), APP, INSTANCE, COMPOSE, KEY_PROVIDER);
    }

    /// A document with another shape (here a GPU policy added) has another hash.
    function test_ADocumentWithMoreFieldsIsRefused() public {
        bytes memory document = bytes.concat(
            '{"app_id":"7304267bd32e1b49e6efa19ab73a756ee30c14e7","compose_hash":"66dfe96ab4493d8f81c21567f409b4bca40502907adf9f5472196d503a34b513","gpu_policy_hash":"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a","init_script_hashes":[],"instance_id":"b3416d34c3cc2fbb760d38767ce6094807161e5b","key_provider":"kms","key_provider_id":"',
            "3059301306072a8648ce3d020106082a8648ce3d03010703420004e8e325a477b0bf22800dc927a46c68638938d283fe73d1f9028eeac7028193f3470122193875f598b7addc503e534712ab437b4120776bbac32ddf8897f844ee",
            '","version":3}'
        );
        bytes memory field =
            bytes.concat(bytes1(0x03), sha256(bytes.concat("dstack-mr-config-v3:", bytes1(0), document)), bytes15(0));
        vm.expectRevert(DstackDocumentVerifier.BadConfigId.selector);
        verifier.attest(_with(quote, MR_CONFIG_ID, field), APP, INSTANCE, COMPOSE, KEY_PROVIDER);
    }

    // ------------------------------------------------------------ inherited checks still apply

    function test_OutOfDatePlatformAndForgedQuoteAreRefused() public {
        dcap.set(true, 4, 2);
        vm.expectRevert(abi.encodeWithSelector(TdxQuoteVerifier.PlatformNotAccepted.selector, uint8(4)));
        verifier.attest(quote, APP, INSTANCE, COMPOSE, KEY_PROVIDER);
        dcap.set(false, 0, 2);
        vm.expectRevert();
        verifier.attest(quote, APP, INSTANCE, COMPOSE, KEY_PROVIDER);
    }

    function test_EmptyListIsRefusedAtDeployment() public {
        vm.expectRevert(TdxQuoteVerifier.BadConfig.selector);
        new DstackDocumentVerifier(dcap, 1, new bytes32[](0));
    }
}
