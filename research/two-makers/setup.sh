#!/bin/sh
# Brings in the reviewed Nitro verifier (MIT) at the commit we checked, and its test helpers.
# Run from this folder; then: forge test
set -e
rm -rf /tmp/nitro-validator
git clone -q https://github.com/base/nitro-validator /tmp/nitro-validator
git -C /tmp/nitro-validator checkout -q 0ea0d12
mkdir -p src/nv lib
cp -r /tmp/nitro-validator/src/. src/nv/
cp /tmp/nitro-validator/test/helpers/HintedNitroTestHelpers.sol /tmp/nitro-validator/test/helpers/ECDSA384HintCollector.sol test/
sed -i 's#"../../src/#"../src/nv/#' test/HintedNitroTestHelpers.sol test/ECDSA384HintCollector.sol
git clone -q --depth 1 https://github.com/foundry-rs/forge-std lib/forge-std
