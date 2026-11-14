# Compiled USDC contract, for tests only

These two files are Circle's `FiatTokenV2_2` (the USDC implementation) and its
`SignatureChecker` library, compiled without any change so that the x402 tests
run against the real token code.

- Source: https://github.com/circlefin/stablecoin-evm, commit
  `fc85788bc7c23cefe3df1a757133048bfddadeaa`
- Compiler: solc 0.6.12, optimizer on, 10,000,000 runs, OpenZeppelin Contracts 3.4.2
- Library link address used at compile time:
  `0x00000000000000000000000000000000005167C4` (the test places the library there)
- License of these two files: Apache-2.0, see `LICENSE` in this folder.
  The rest of this repository is CC0-1.0.

To rebuild them:

    solc-0.6.12 --optimize --optimize-runs 10000000 \
      @openzeppelin/=<path to @openzeppelin 3.4.2>/ \
      --libraries "contracts/util/SignatureChecker.sol:SignatureChecker:0x00000000000000000000000000000000005167C4" \
      --combined-json bin,bin-runtime \
      contracts/v2/FiatTokenV2_2.sol contracts/util/SignatureChecker.sol
