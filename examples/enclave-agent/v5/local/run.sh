#!/usr/bin/env bash
# Local end-to-end test of the fifth program, on a local chain, with nothing from Base Sepolia:
# Circle's USDC code (test/usdc), our registry and AgentAllowance, the x402 shop of the fourth
# program's test, a stand-in for Phala's AI gateway (gateway.mjs) and the DCAP stub of the unit
# tests in place of Intel's check. It checks that the agent buys only on a verified "BUY": no API
# key, a "SKIP", and each kind of cheating gateway mean no purchase; an honest gateway means
# purchases, never more than the allowance. Throwaway keys, made here and never written down.
# Run from the repository root after `forge build`: bash examples/enclave-agent/v5/local/run.sh
set -euo pipefail
cd "$(dirname "$0")/../../../.."
RPC=http://127.0.0.1:8545
HERE=examples/enclave-agent/v5
V4=examples/enclave-agent/v4
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

# Two certificates for localhost, both trusted by the agent's TLS: only the pin tells them apart.
TMP=$(mktemp -d)
for n in good other; do
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj /CN=localhost \
    -addext subjectAltName=DNS:localhost -keyout $TMP/$n.key -out $TMP/$n.pem 2>/dev/null
done
cat $TMP/good.pem $TMP/other.pem > $TMP/ca.pem
APIKEY=local_$(openssl rand -hex 16)
node $HERE/local/gateway.mjs 8443 8444 $TMP/good.pem $TMP/good.key $TMP/other.pem $TMP/other.key $APIKEY &
mode() { curl -fsS -X POST "http://127.0.0.1:8444/mode?to=$1" >/dev/null; }
STUB=$(create "$(artifact out/TdxEnrollment.t.sol/DcapStub.json)")

PRICE=20000 LIMIT=50000
node $V4/local/shop.mjs $RPC $USDC $SHOP $PRICE $FACILITATOR &
start_agent() { # $1: the API key given to the machine, or nothing
  CHAIN_ID=84532 REGISTRY=$REG AGENT_ID=1 ALLOWANCE=$BOX ALLOWANCE_ID=1 ASSET=$USDC CAP=20000 DRAW=30000 EVERY=2 TICK=1 \
    RPC_URL=$RPC SHOP_URL=http://127.0.0.1:8402/page NETWORK=eip155:84532 \
    AI_HOST=localhost AI_PORT=8443 AI_MODEL=local/stand-in DCAP=$STUB AI_MAX_PER_DAY=1000 \
    NODE_EXTRA_CA_CERTS=$TMP/ca.pem PHALA_AI_API_KEY="$1" node $HERE/agent.js &
  AGENT_PID=$!
  for i in $(seq 50); do curl -fsS $AGENT/ >/dev/null 2>&1 && break; sleep 0.2; done
  KEY=$(curl -fsS $AGENT/ | python3 -c 'import json,sys; print(json.load(sys.stdin)["sessionKey"])')
}
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
paid() { cast call --rpc-url $RPC $USDC "balanceOf(address)(uint256)" $SHOP | cut -d' ' -f1; }
run_for() { for i in $(seq $1); do FROM=$RELAYER bash $V4/relay.sh $AGENT $RPC >/dev/null || true; sleep 1; done; }
last() { curl -fsS $AGENT/ | python3 -c 'import json,sys; d=(json.load(sys.stdin)["decisions"] or [{}])[0]; print(d.get("answer"), "|", d.get("verified"), "|", d.get("reason"))'; }
AGENT=http://127.0.0.1:8080

# 1. No API key: the agent draws, but never buys.
start_agent ""
enroll
ACCOUNT=$(cast call --rpc-url $RPC $REG "accountOf(uint256)(address)" 1)
send $SPONSOR $USDC "approve(address,uint256)" $BOX 1000000
send $SPONSOR $BOX "open(address,address,uint128,uint64,uint256)" $ACCOUNT $USDC $LIMIT 86400 200000
run_for 6
[ "$(paid)" = 0 ] || fail "bought without an API key"
case "$(last)" in *"no API key given"*) ;; *) fail "no-key decision: $(last)";; esac
[ "$(curl -fsS $AGENT/ | grep -c "$APIKEY")" = 0 ] || fail "API key shown"
echo "no API key: no purchase ($(last))"

# 2. With the key (restart: new key, enrolled on the same account), against each cheating gateway.
kill $AGENT_PID; wait $AGENT_PID 2>/dev/null || true
start_agent "$APIKEY"
enroll
[ "$(curl -fsS $AGENT/ | grep -c "$APIKEY")" = 0 ] || fail "API key shown"
for path in /mint /buy /pay /draw /sign /ask /decide; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$AGENT$path?to=$SHOP&amount=1")
  [ "$code" = 400 ] || fail "$path answered $code"
done
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST $AGENT/)" = 405 ] || fail "POST accepted"
check_no_buy() { # $1 mode, $2 expected text in the last decision
  mode $1; run_for 4
  [ "$(paid)" = 0 ] || fail "$1: the agent bought"
  case "$(last)" in *"$2"*) echo "$1: no purchase ($(last))";; *) fail "$1: last decision $(last)";; esac
}
check_no_buy skip "SKIP | True"
check_no_buy bad-signature "receipt: signature"
check_no_buy bad-answer-hash "receipt: answer hash"
check_no_buy unverified-upstream "model server not verified"
check_no_buy wrong-tls "gateway TLS key is not attested"
check_no_buy stale-nonce "not bound to our nonce"
check_no_buy no-receipt "model: no receipt"
mode honest
send $DEPLOYER $STUB "set(bool,uint8,uint16)" false 0 2; check_no_buy honest "gateway quote: not genuine"
send $DEPLOYER $STUB "set(bool,uint8,uint16)" true 1 2; check_no_buy honest "platform not up to date"
send $DEPLOYER $STUB "set(bool,uint8,uint16)" true 0 2

# 3. Honest gateway: verified "BUY"s, within the allowance, then nothing more.
run_for 20
STATE=$(curl -fsS $AGENT/)
p=$(paid); held=$(cast call --rpc-url $RPC $USDC "balanceOf(address)(uint256)" $ACCOUNT | cut -d' ' -f1)
left=$(cast call --rpc-url $RPC $BOX "available(uint256)(uint256)" 1 | cut -d' ' -f1)
echo "honest gateway: shop paid $p, account holds $held, allowance available $left; last decision $(last)"
[ "$p" = 40000 ] || fail "expected two purchases of $PRICE, the shop has $p"
[ "$left" = 0 ] || fail "the allowance still has $left"
[ $((p + held)) -le $LIMIT ] || fail "spent more than the limit"
echo "$STATE" | python3 -c 'import json,sys; s=json.load(sys.stdin); g=s["gateway"]; assert g and g["keysetDigest"].startswith("sha256:"), g; assert all(d["verified"] and d["answer"]=="BUY" for d in s["decisions"][:2]), s["decisions"][:2]'
echo "OK"
