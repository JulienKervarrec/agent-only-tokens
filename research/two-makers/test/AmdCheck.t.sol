// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {P384Verifier} from "../src/nv/P384Verifier.sol";
import {Sha2Ext} from "../src/nv/Sha2Ext.sol";
import {P384HintCollector} from "./HintedNitroTestHelpers.sol";

/// RSA-4096 PSS (SHA-384, MGF1-SHA-384, 48-byte salt, e = 65537): how AMD signs its certificates.
library RsaPss4096 {
    uint256 constant K = 512; // bytes in the modulus
    uint256 constant HL = 48; // SHA-384 output
    uint256 constant DBL = K - HL - 1; // 463

    function verify(bytes memory message, bytes memory sig, bytes memory n) internal view returns (bool) {
        if (sig.length != K || n.length != K) return false;
        bytes memory em = _modexp(sig, n);
        if (uint8(em[K - 1]) != 0xbc) return false;
        if (uint8(em[0]) & 0x80 != 0) return false; // emBits = 4095
        bytes memory h = new bytes(HL);
        for (uint256 i; i < HL; ++i) h[i] = em[DBL + i];
        // DB = maskedDB xor MGF1(H)
        bytes memory db = new bytes(DBL);
        bytes memory seed = new bytes(HL + 4);
        for (uint256 i; i < HL; ++i) seed[i] = h[i];
        for (uint256 c; c * HL < DBL; ++c) {
            seed[HL + 3] = bytes1(uint8(c));
            bytes memory m = Sha2Ext.sha384(seed, 0, seed.length);
            for (uint256 j; j < HL && c * HL + j < DBL; ++j) db[c * HL + j] = em[c * HL + j] ^ m[j];
        }
        db[0] &= 0x7f;
        uint256 saltAt = DBL - HL; // 415
        for (uint256 i; i < saltAt - 1; ++i) if (db[i] != 0) return false;
        if (uint8(db[saltAt - 1]) != 0x01) return false;
        // H' = SHA-384(0x00 x 8 || SHA-384(message) || salt)
        bytes memory mh = Sha2Ext.sha384(message, 0, message.length);
        bytes memory mp = new bytes(8 + HL + HL);
        for (uint256 i; i < HL; ++i) {
            mp[8 + i] = mh[i];
            mp[8 + HL + i] = db[saltAt + i];
        }
        return keccak256(Sha2Ext.sha384(mp, 0, mp.length)) == keccak256(h);
    }

    function _modexp(bytes memory base, bytes memory n) private view returns (bytes memory out) {
        bytes memory input = abi.encodePacked(uint256(K), uint256(3), uint256(K), base, hex"010001", n);
        out = new bytes(K);
        bool ok;
        assembly {
            ok := staticcall(gas(), 0x05, add(input, 32), mload(input), add(out, 32), K)
        }
        require(ok, "modexp");
    }
}

contract Pss is Test {
    function check(bytes memory m, bytes memory s, bytes memory n) external view returns (bool) {
        return RsaPss4096.verify(m, s, n);
    }
}

contract AmdCheck is Test {
    uint256 constant CAP = 16_777_216;
    Pss pss;
    P384Verifier p384;
    P384HintCollector hints;

    function setUp() public {
        pss = new Pss();
        p384 = new P384Verifier();
        hints = new P384HintCollector();
    }

    function _f(string memory n) internal view returns (bytes memory) {
        return vm.readFileBinary(string.concat("test/data/amd/", n, ".bin"));
    }

    function test_AmdCertificateChainVerifiesOnChain() public view {
        uint256 g = gasleft();
        assertTrue(pss.check(_f("ask_tbs"), _f("ask_sig"), _f("ark_n")), "ARK signs ASK");
        uint256 g1 = g - gasleft();
        g = gasleft();
        assertTrue(pss.check(_f("vcek_tbs"), _f("vcek_sig"), _f("ask_n")), "ASK signs VCEK");
        uint256 g2 = g - gasleft();
        console.log("RSA-PSS check ARK->ASK gas", g1);
        console.log("RSA-PSS check ASK->VCEK gas", g2);
        assertLt(g1, CAP);
        assertLt(g2, CAP);
    }

    function test_AmdReportSignatureVerifiesOnChain() public {
        bytes memory signed = _f("report_signed");
        bytes memory hash = Sha2Ext.sha384(signed, 0, signed.length);
        bytes memory sig = _f("report_sig");
        bytes memory pub = _f("vcek_pub");
        bytes memory h = hints.collectVerifyHints(hash, sig, pub);
        uint256 g = gasleft();
        bool ok = p384.verifyP384SignatureWithHints(hash, sig, pub, h);
        g -= gasleft();
        console.log("report P-384 signature gas", g);
        assertTrue(ok);
        assertLt(g, CAP);
    }

    function test_ChangedReportIsRefused() public {
        bytes memory signed = _f("report_signed");
        bytes memory sig = _f("report_sig");
        bytes memory pub = _f("vcek_pub");
        bytes memory h = hints.collectVerifyHints(Sha2Ext.sha384(signed, 0, signed.length), sig, pub);
        signed[0x50] ^= 0x01; // one bit of report_data
        bytes memory hash = Sha2Ext.sha384(signed, 0, signed.length);
        bool ok;
        try p384.verifyP384SignatureWithHints(hash, sig, pub, h) returns (bool r) { ok = r; } catch {}
        assertFalse(ok);
    }

    function test_ChangedCertificateIsRefused() public view {
        bytes memory tbs = _f("vcek_tbs");
        tbs[100] ^= 0x01;
        assertFalse(pss.check(tbs, _f("vcek_sig"), _f("ask_n")));
    }
}
