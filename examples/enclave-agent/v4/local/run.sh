#!/usr/bin/env bash
# Local end-to-end test of the fourth program, on a local chain, with nothing from Base Sepolia:
# Circle's USDC code (test/usdc), our registry and AgentAllowance, a stand-in x402 shop, and the
# program itself started from agent.js with the settings the compose file would give it.
# It checks that the agent draws and pays by itself, never more than its allowance, and that
# nothing from outside can make it sign. Throwaway keys, made here and never written down.
# Run from the repository root after `forge build`: bash examples/enclave-agent/v4/local/run.sh
set -euo pipefail
cd "$(dirname "$0")/../../../.."
RPC=http://127.0.0.1:8545
HERE=examples/enclave-agent/v4
fail() { echo "FAIL: $*"; exit 1; }
cleanup() { kill $(jobs -p) 2>/dev/null || true; }
trap cleanup EXIT

anvil --chain-id 84532 --port 8545 --silent --disable-code-size-limit &
for i in $(seq 50); do cast chain-id --rpc-url $RPC >/dev/null 2>&1 && break; sleep 0.2; done
accounts=($(cast rpc --rpc-url $RPC eth_accounts | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)))'))
DEPLOYER=${accounts[0]} SPONSOR=${accounts[1]} FACILITATOR=${accounts[2]} SHOP=${accounts[3]} RELAYER=${accounts[4]}
send() { cast send --rpc-url $RPC --unlocked --from "$@" >/dev/null; }
create() { cast send --rpc-url $RPC --unlocked --from $DEPLOYER --create "$@" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])'; }
artifact() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); b=d["bytecode"]; print(b if isinstance(b,str) else b["object"])' "$1"; }

# Circle's USDC, with its signature library at the address it was linked with.
cast rpc --rpc-url $RPC anvil_setCode 0x00000000000000000000000000000000005167C4 \
  "$(python3 -c 'import json; print(json.load(open("test/usdc/SignatureChecker.json"))["deployedBytecode"])')" >/dev/null
USDC=$(create "$(artifact test/usdc/FiatTokenV2_2.json)")
send $DEPLOYER $USDC "initialize(string,string,string,uint8,address,address,address,address)" "USD Coin" USDC USD 6 $DEPLOYER $DEPLOYER $DEPLOYER $DEPLOYER
send $DEPLOYER $USDC "initializeV2(string)" "USD Coin"
send $DEPLOYER $USDC "initializeV2_1(address)" 0x000000000000000000000000000000000000dEaD
send $DEPLOYER $USDC "initializeV2_2(address[],string)" "[]" USDC
send $DEPLOYER $USDC "configureMinter(address,uint256)" $DEPLOYER 1000000000
send $DEPLOYER $USDC "mint(address,uint256)" $SPONSOR 1000000

# Registry with three throwaway attesters (threshold 2), and the allowance contract.
A1=$(cast wallet new --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["private_key"])')
A2=$(cast wallet new --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["private_key"])')
A3=$(cast wallet new --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["private_key"])')
ATT="[$(cast wallet address $A1),$(cast wallet address $A2),$(cast wallet address $A3)]"
REG=$(create "$(artifact out/AttestedAgentRegistry.sol/AttestedAgentRegistry.json)$(cast abi-encode 'f(address[],uint256,uint256,uint64,uint64,address,address)' "$ATT" 2 0 86400 60 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 | cut -c3-)")
BOX=$(create "$(artifact out/AgentAllowance.sol/AgentAllowance.json)")

# The program, with the settings its compose file gives it, and the shop.
PRICE=20000 LIMIT=50000
node $HERE/local/shop.mjs $RPC $USDC $SHOP $PRICE $FACILITATOR &
start_agent() {
  CHAIN_ID=84532 REGISTRY=$REG AGENT_ID=1 ALLOWANCE=$BOX ALLOWANCE_ID=1 ASSET=$USDC CAP=20000 DRAW=30000 EVERY=2 TICK=1 \
    RPC_URL=$RPC SHOP_URL=http://127.0.0.1:8402/page NETWORK=eip155:84532 node $HERE/agent.js &
  AGENT_PID=$!
  for i in $(seq 50); do curl -fsS $AGENT/ >/dev/null 2>&1 && break; sleep 0.2; done
  KEY=$(curl -fsS $AGENT/ | python3 -c 'import json,sys; print(json.load(sys.stdin)["sessionKey"])')
}
# The sponsor enrolls the agent's current key; two attesters sign.
enroll() {
  local evid nonce d sigs
  evid=$(cast keccak local-test)
  nonce=$(cast call --rpc-url $RPC $REG "enrollmentNonce(uint256)(uint256)" 1)
  d=$(cast call --rpc-url $RPC $REG "hashAttestedEnrollment(uint256,address,bytes32,address,uint256,uint64)(bytes32)" 1 $KEY $evid $SPONSOR $nonce 9999999999)
  sigs=$(python3 - "$(cast wallet address $A1)" "$(cast wallet sign --no-hash $d --private-key $A1)" "$(cast wallet address $A2)" "$(cast wallet sign --no-hash $d --private-key $A2)" <<'PY'
import sys
a=[(sys.argv[1].lower(),sys.argv[2]),(sys.argv[3].lower(),sys.argv[4])]
print("[" + ",".join(s for _, s in sorted(a)) + "]")
PY
)
  send $SPONSOR $REG "enroll(uint256,address,bytes32,uint64,bytes[])" 1 $KEY $evid 9999999999 "$sigs"
}
AGENT=http://127.0.0.1:8080
start_agent
FIRST_KEY=$KEY
enroll
ACCOUNT=$(cast call --rpc-url $RPC $REG "accountOf(uint256)(address)" 1)
send $SPONSOR $USDC "approve(address,uint256)" $BOX 1000000
send $SPONSOR $BOX "open(address,address,uint128,uint64,uint256)" $ACCOUNT $USDC $LIMIT 86400 200000

# Nothing from outside makes it sign.
for path in /mint /buy /pay /draw /sign; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$AGENT$path?to=$SHOP&amount=1")
  [ "$code" = 400 ] || fail "$path answered $code"
done
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST $AGENT/)" = 405 ] || fail "POST accepted"

# Let it run, relaying any draw it signs, for 25 seconds.
for i in $(seq 25); do FROM=$RELAYER bash $HERE/relay.sh $AGENT $RPC >/dev/null || true; sleep 1; done
STATE=$(curl -fsS $AGENT/)
paid=$(cast call --rpc-url $RPC $USDC "balanceOf(address)(uint256)" $SHOP | cut -d' ' -f1)
held=$(cast call --rpc-url $RPC $USDC "balanceOf(address)(uint256)" $ACCOUNT | cut -d' ' -f1)
left=$(cast call --rpc-url $RPC $BOX "available(uint256)(uint256)" 1 | cut -d' ' -f1)
echo "shop paid $paid, account holds $held, allowance available $left"
echo "state: $(echo "$STATE" | python3 -c 'import json,sys; s=json.load(sys.stdin); print({k: s[k] for k in ("enrolled","balance","available","lastError","ticks")}, len(s["purchases"]), "purchases")')"
[ "$paid" = 40000 ] || fail "expected two purchases of $PRICE, the shop has $paid"
[ "$left" = 0 ] || fail "the allowance still has $left"
[ $((paid + held)) -le $LIMIT ] || fail "spent more than the limit"
echo "first key: two purchases of $PRICE under a limit of $LIMIT a day; then it stopped"

# Restart: a new process, hence a new key, enrolled on the same account. The budget stays spent.
kill $AGENT_PID; wait $AGENT_PID 2>/dev/null || true
start_agent
[ "$KEY" != "$FIRST_KEY" ] || fail "the key did not change"
enroll
for i in $(seq 10); do FROM=$RELAYER bash $HERE/relay.sh $AGENT $RPC >/dev/null || true; sleep 1; done
paid2=$(cast call --rpc-url $RPC $USDC "balanceOf(address)(uint256)" $SHOP | cut -d' ' -f1)
enrolled=$(curl -fsS $AGENT/ | python3 -c 'import json,sys; print(json.load(sys.stdin)["enrolled"])')
[ "$enrolled" = True ] || fail "the new key is not enrolled"
[ "$paid2" = "$paid" ] || fail "after the restart the shop got $((paid2 - paid)) more"
echo "after a restart with a new key: enrolled, no more payment (the shop still has $paid2)"
echo "OK"
