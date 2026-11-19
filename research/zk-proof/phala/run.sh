#!/usr/bin/env bash
# Runs inside the Phala machine. Builds aot-zkp, proves our quote with Groth16, serves /out.
# No key, no wallet: the input is public (quote + Intel collateral), the output is a public proof.
set -euo pipefail
mkdir -p /out
exec > >(tee -a /out/log.txt) 2>&1
echo "start $(date -u +%FT%TZ)"
apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates curl git python3 >/dev/null
# Progress and results, public data only, at the machine's port 8080.
(cd /out && python3 -m http.server 8080 >/dev/null 2>&1 &)
# Docker client only: RISC Zero runs its Groth16 prover image through the machine's Docker.
curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-27.3.1.tgz \
  | tar xz -C /usr/local/bin --strip-components=1 docker/docker
docker version --format '{{.Server.Version}}'

mkdir -p /src && cd /src && echo "$BUNDLE" | base64 -d | tar xz
git clone -q --depth 1 -b v1.1.0 https://github.com/automata-network/automata-dcap-attestation /a
test "$(git -C /a rev-parse HEAD)" = 9c96312657f2a905003f6ebf565d5742422f24a2
mkdir -p vendor guest
cp -r /a/rust-crates/libraries/dcap-rs vendor/ && rm -rf vendor/dcap-rs/tests
python3 patch_dcap.py vendor/dcap-rs/Cargo.toml
cp /a/rust-crates/libraries/zkvm/src/risc0/guest/v1_1/elf/guest guest/dcap-v1_1.elf
echo "18085185d2bed16c459ddd755a175ca28a736329b5e73494654eb712a2c2ef09  guest/dcap-v1_1.elf" | sha256sum -c
# Automata's lock file: the RISC Zero versions it pins make proofs for the v3.0.0 verifier on Base.
cp /a/rust-crates/Cargo.lock .

# The quote: by default ours as published in the repo (v0.4.6); with QUOTE_URL, the answer of a
# running agent (JSON with a "quote" field), kept whole in /out/agent.json. Then the Intel
# collateral as Base Sepolia has it now.
if [ -n "${QUOTE_URL:-}" ]; then
  curl -fsSL -o /out/agent.json "$QUOTE_URL"
  python3 -c 'import json; print(json.load(open("/out/agent.json"))["quote"].removeprefix("0x"))' > quote.hex
else
  curl -fsSL -o quote.hex https://raw.githubusercontent.com/JulienKervarrec/agent-only-tokens/2719c394d1eea436a3ed13be27c129dda26e8a9f/test/experimental/phala/quote-own-prelaunch.hex
  echo "b573d55fd70b98cf62fe78b334c040bb5e454c49ec46cf860df19423fadc5a8f  quote.hex" | sha256sum -c
fi
python3 fetch_collateral.py col
cp -r col quote.hex /out/

cargo build --release
echo "built $(date -u +%FT%TZ)"
# RISC0_WORK_DIR=aotwork is a relative path: Docker reads "aotwork:/mnt" as the named volume
# aotwork, which this container also mounts at /data/aotwork.
cd /data && RISC0_INFO=1 RUST_LOG=info /src/target/release/aot-zkp prove /src/quote.hex /src/col /out
echo "finished $(date -u +%FT%TZ)"
touch /out/DONE
sleep infinity
