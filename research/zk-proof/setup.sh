#!/bin/sh
# Prepares this folder for `cargo build --release`: Automata's dcap-rs and DCAP v1.1 RISC Zero
# program at the release commit (checked by hash), our quote from this repository, and the
# Intel data as Base Sepolia has it now. Read-only network access, no key.
set -eu
cd "$(dirname "$0")"
REV=9c96312657f2a905003f6ebf565d5742422f24a2 # automata-dcap-attestation v1.1.0
rm -rf .automata vendor guest
git clone -q --depth 1 -b v1.1.0 https://github.com/automata-network/automata-dcap-attestation .automata
test "$(git -C .automata rev-parse HEAD)" = "$REV"
mkdir -p vendor guest
cp -r .automata/rust-crates/libraries/dcap-rs vendor/ && rm -rf vendor/dcap-rs/tests
python3 phala/patch_dcap.py vendor/dcap-rs/Cargo.toml
cp .automata/rust-crates/libraries/zkvm/src/risc0/guest/v1_1/elf/guest guest/dcap-v1_1.elf
echo "18085185d2bed16c459ddd755a175ca28a736329b5e73494654eb712a2c2ef09  guest/dcap-v1_1.elf" | sha256sum -c
# Automata's lock file pins the RISC Zero versions whose proofs the v3.0.0 verifier accepts.
cp .automata/rust-crates/Cargo.lock .
rm -rf .automata
cp ../../test/experimental/phala/quote-own-prelaunch.hex quote.hex
echo "b573d55fd70b98cf62fe78b334c040bb5e454c49ec46cf860df19423fadc5a8f  quote.hex" | sha256sum -c
python3 fetch_collateral.py col
echo "ready: cargo build --release, then ./target/release/aot-zkp exec quote.hex col out"
