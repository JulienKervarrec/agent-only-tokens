#!/usr/bin/env bash
# Replays every check of this repository, in one command, on a fresh machine with Foundry,
# Node 22, Python 3 and (for the proofs) Halmos. Nothing is sent to any chain: forks and
# local chains only. Step 7.2 of the plan.
#
#   bash tools/reproduce.sh            everything that needs no network but package registries
#   BASE_SEPOLIA_RPC=https://sepolia.base.org bash tools/reproduce.sh   also the fork tests
#
# Each step prints one line; the script stops at the first failure.
set -euo pipefail
cd "$(dirname "$0")/.."
step() { printf '%-58s' "$1"; shift; if out=$("$@" 2>&1); then echo "ok"; else echo "FAILED"; echo "$out" | tail -30; exit 1; fi; }
[ -d node_modules ] || step "npm ci" npm ci
[ -d lib/forge-std ] || step "forge-std v1.9.7" git clone --depth 1 --branch v1.9.7 https://github.com/foundry-rs/forge-std lib/forge-std
step "recorded data matches its SHA256SUMS" python3 tools/datasets.py --check
step "formatting of the contracts" forge fmt --check src
step "unit, fuzz and invariant tests" env -u BASE_SEPOLIA_RPC forge test
step "figures quoted in the documentation" python3 tools/figures.py
step "addresses cited are recorded" python3 tools/deployments.py
step "conformance suites catch every faulty version" python3 tools/conformance.py
step "ERC text and its printed reference implementation" python3 tools/erc_package.py "$(mktemp -d)" --check
step "registry monitor page" python3 tools/monitor_page.py --check
step "fourth agent program, end to end, local chain" bash examples/enclave-agent/v4/local/run.sh
step "fifth agent program (model decisions), local chain" bash examples/enclave-agent/v5/local/run.sh
step "sixth agent program (token, journal), local chain" bash examples/enclave-agent/v6/local/run.sh
step "incident drill, local chain" bash examples/operations/drill.sh
if command -v halmos >/dev/null; then
  step "symbolic proofs (Halmos)" halmos --match-contract "AgentOnlyProps|RegistryProps|LoanProps|AllowanceProps|AccountProps"
else
  echo "symbolic proofs (Halmos)                                  skipped: pip install halmos==0.3.3"
fi
if [ -n "${BASE_SEPOLIA_RPC:-}" ]; then
  step "tests against a copy of Base Sepolia" env FOUNDRY_EVM_VERSION=osaka forge test --match-path 'test/fork/*'
else
  echo "tests against a copy of Base Sepolia                      skipped: set BASE_SEPOLIA_RPC"
fi
echo "all checks passed"
