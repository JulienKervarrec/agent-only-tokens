// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {NitroValidator} from "../src/nv/NitroValidator.sol";
import {CertManager} from "../src/nv/CertManager.sol";
import {ICertManager} from "../src/nv/ICertManager.sol";
import {P384Verifier} from "../src/nv/P384Verifier.sol";
import {Sha2Ext} from "../src/nv/Sha2Ext.sol";
import {LibBytes} from "../src/nv/LibBytes.sol";
import {CborDecode, CborElement, LibCborElement} from "../src/nv/CborDecode.sol";
import {P384HintCollector} from "./HintedNitroTestHelpers.sol";

contract Parse is NitroValidator {
    constructor(ICertManager c, P384Verifier p) NitroValidator(c, p) {}
    function parse(bytes memory tbs) external pure returns (Ptrs memory) { return _parseAttestation(tbs); }
}

contract NitroCheck is Test {
    using LibBytes for bytes;
    using CborDecode for bytes;
    using LibCborElement for CborElement;

    uint256 constant CAP = 16_777_216;
    P384Verifier p384; CertManager certs; NitroValidator validator; Parse parser; P384HintCollector hints;
    bytes doc;

    function setUp() public {
        vm.warp(1767472867); // the document's own time, 3 January 2026
        p384 = new P384Verifier();
        certs = new CertManager(p384, address(this), address(this));
        validator = new NitroValidator(certs, p384);
        parser = new Parse(certs, p384);
        hints = new P384HintCollector();
        doc = vm.readFileBinary("test/data/nitro-sample.bin");
    }

    function _cacheChain(bytes memory tbs) internal returns (uint256 txs, uint256 total, uint256 worst) {
        NitroValidator.Ptrs memory p = parser.parse(tbs);
        bytes32 parent;
        for (uint256 i; i < p.cabundle.length; ++i) {
            bytes memory c = tbs.slice(p.cabundle[i]);
            bytes memory h = i == 0 ? bytes("") : hints.collectCertSignatureHints(c, certs.loadVerified(parent).pubKey);
            uint256 g = gasleft(); parent = certs.verifyCACertWithHints(c, parent, h); g -= gasleft();
            txs++; total += g; if (g > worst) worst = g;
            console.log("CA cert", i, "gas", g);
        }
        bytes memory leaf = tbs.slice(p.cert);
        bytes memory lh = hints.collectCertSignatureHints(leaf, certs.loadVerified(parent).pubKey);
        uint256 g2 = gasleft(); certs.verifyClientCertWithHints(leaf, parent, lh); g2 -= gasleft();
        txs++; total += g2; if (g2 > worst) worst = g2;
        console.log("leaf cert gas", g2);
    }

    function _sigHints(bytes memory tbs, bytes memory sig) internal returns (bytes memory) {
        // The chain is cached by now: walking it again returns the leaf's key.
        bytes memory pub = _leafKey(tbs, parser.parse(tbs));
        return hints.collectVerifyHints(Sha2Ext.sha384(tbs, 0, tbs.length), sig, pub);
    }

    function _leafKey(bytes memory tbs, NitroValidator.Ptrs memory p) internal returns (bytes memory) {
        bytes32 parent;
        for (uint256 i; i < p.cabundle.length; ++i) parent = certs.verifyCACertWithHints(tbs.slice(p.cabundle[i]), parent, "");
        return certs.verifyClientCertWithHints(tbs.slice(p.cert), parent, "").pubKey;
    }

    function test_RealNitroDocumentVerifiesUnderTheCap() public {
        (bytes memory tbs, bytes memory sig) = validator.decodeAttestationTbs(doc);
        (uint256 txs, uint256 total, uint256 worst) = _cacheChain(tbs);
        bytes memory h = _sigHints(tbs, sig);
        uint256 g = gasleft();
        NitroValidator.Ptrs memory p = validator.validateAttestationWithHints(tbs, sig, h);
        g -= gasleft();
        console.log("document gas (chain cached)", g);
        console.log("first time: transactions", txs + 1, "total gas", total + g);
        assertLt(g, CAP); assertLt(worst, CAP);
        assertEq(p.timestamp, 1767472867402);
        assertEq(p.userData.length(), 20, "user_data carries 20 bytes");
    }

    function test_ChangedDocumentIsRefused() public {
        (bytes memory tbs, bytes memory sig) = validator.decodeAttestationTbs(doc);
        _cacheChain(tbs);
        bytes memory h = _sigHints(tbs, sig);
        NitroValidator.Ptrs memory p = parser.parse(tbs);
        tbs[p.userData.start()] ^= 0x01; // one bit of user_data
        vm.expectRevert();
        validator.validateAttestationWithHints(tbs, sig, h);
    }

    function test_ExpiredLeafCertificateIsRefused() public {
        (bytes memory tbs,) = validator.decodeAttestationTbs(doc);
        NitroValidator.Ptrs memory p = parser.parse(tbs);
        bytes32 parent;
        for (uint256 i; i < p.cabundle.length; ++i) {
            bytes memory c = tbs.slice(p.cabundle[i]);
            bytes memory h = i == 0 ? bytes("") : hints.collectCertSignatureHints(c, certs.loadVerified(parent).pubKey);
            parent = certs.verifyCACertWithHints(c, parent, h);
        }
        bytes memory leaf = tbs.slice(p.cert);
        bytes memory lh = hints.collectCertSignatureHints(leaf, certs.loadVerified(parent).pubKey);
        vm.warp(1767483628 + 1); // just after the leaf's end, 23:40:28 UTC: three hours of life
        vm.expectRevert();
        certs.verifyClientCertWithHints(leaf, parent, lh);
    }
}
