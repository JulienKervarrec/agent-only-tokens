// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IDcapAttestation} from "../src/experimental/TdxQuoteVerifier.sol";
import {TdxEnrollmentVerifier} from "../src/experimental/TdxEnrollmentVerifier.sol";

/// Testnet: our TDX enrollment verifier calling the real Automata DCAP verifier on Base Sepolia,
/// with a real Intel TDX quote (test/experimental/tdx/quote-v4.hex). That quote's platform is
/// "out of date" (level 4) on Automata's collateral, so this deployment accepts levels 0 and 4.
contract SepoliaTdx is Script {
    IDcapAttestation constant DCAP = IDcapAttestation(0xaDdeC7e85c2182202b66E331f2a4A0bBB2cEEa1F);
    bytes32 constant REAL_CODE = 0x7dda0b4a87de3d2ad86eccd9d37cb9cc01bf17d97eb39abb2eabe2e8a1e81ce6;

    function run() external {
        bytes memory quote = vm.parseBytes(vm.readFile("test/experimental/tdx/quote-v4.hex"));
        bytes32[] memory approved = new bytes32[](1);
        approved[0] = REAL_CODE;
        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));
        TdxEnrollmentVerifier v = new TdxEnrollmentVerifier(DCAP, 1 | (1 << 4), approved);
        v.attest(quote);
        vm.stopBroadcast();
        require(v.attested(bytes32(0)), "not attested");
        console.log("verifier", address(v));
    }
}
