#!/usr/bin/env bash
# Local end-to-end test of the sixth program, on a local chain, with nothing from Base Sepolia:
# Circle's USDC code, our registry, AgentAllowance and AgentSwap, a collection of the standard, a
# second agent that sells five tokens (one that the rules allow, four that they do not), an x402
# shop whose page tries to steer the agent, a stand-in for Phala's AI gateway that answers BUY to
# everything (a model fully taken over by the page), the DCAP stub, and a stand-in for dstack's
# quote socket. It checks that the agent buys the allowed token and only it, once, at its price,
# within the allowance; that nothing from outside makes it sign; and that its journal replays and
# is bound to the caller's nonce by the quote, and that a changed entry is caught.
# Throwaway keys, made here and never written down.
# Run from the repository root after `forge build`: bash examples/enclave-agent/v6/local/run.sh
set -euo pipefail
cd "$(dirname "$0")/../../../.."
RPC=http://127.0.0.1:8545
HERE=examples/enclave-agent/v6
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

SWAP=$(create "$(artifact out/AgentSwap.sol/AgentSwap.json)")
NFT=$(create "$(artifact out/SepoliaDemo.s.sol/DemoAgentCollection.json)$(cast abi-encode 'f(address)' $REG | cut -c3-)")
OTHER=$(create "$(artifact out/SepoliaDemo.s.sol/TestUSD.json)")

# Two of the three attesters sign each decision, in the order of their addresses.
sigs() { # $1: digest
  python3 - "$(cast wallet address $A1)" "$(cast wallet sign --no-hash $1 --private-key $A1)" "$(cast wallet address $A2)" "$(cast wallet sign --no-hash $1 --private-key $A2)" <<'PY'
import sys
a=[(sys.argv[1].lower(),sys.argv[2]),(sys.argv[3].lower(),sys.argv[4])]
print("[" + ",".join(s for _, s in sorted(a)) + "]")
PY
}
enroll() { # $1 agent id, $2 session key
  local evid nonce d
  evid=$(cast keccak local-test)
  nonce=$(cast call --rpc-url $RPC $REG "enrollmentNonce(uint256)(uint256)" $1)
  d=$(cast call --rpc-url $RPC $REG "hashAttestedEnrollment(uint256,address,bytes32,address,uint256,uint64)(bytes32)" $1 $2 $evid $SPONSOR $nonce 9999999999)
  send $SPONSOR $REG "enroll(uint256,address,bytes32,uint64,bytes[])" $1 $2 $evid 9999999999 "$(sigs $d)"
}
# The venue, approved by the attesters, in force after the notice delay.
evid=$(cast keccak venue-code-read)
d=$(cast call --rpc-url $RPC $REG "hashVenue(address,bool,bytes32,uint64)(bytes32)" $SWAP true $evid 9999999999)
send $SPONSOR $REG "setVenue(address,bool,bytes32,uint64,bytes[])" $SWAP true $evid 9999999999 "$(sigs $d)"
cast rpc --rpc-url $RPC evm_increaseTime 61 >/dev/null; cast rpc --rpc-url $RPC evm_mine >/dev/null
[ "$(cast call --rpc-url $RPC $REG "isVenue(address)(bool)" $SWAP)" = true ] || fail "venue not in force"

# The selling agent (agent 2): a throwaway key that acts on its account directly.
S2=$(cast wallet new --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["private_key"])')
cast rpc --rpc-url $RPC anvil_setBalance $(cast wallet address $S2) 0xde0b6b3a7640000 >/dev/null
enroll 2 $(cast wallet address $S2)
SELLER=$(cast call --rpc-url $RPC $REG "accountOf(uint256)(address)" 2)
as_seller() { cast send --rpc-url $RPC --private-key $S2 $SELLER "execute(address,uint256,bytes)" $1 0 "$(cast calldata "${@:2}")" >/dev/null; }
NOBODY=0x000000000000000000000000000000000000bEEF
for id in 1 2 3 4 5; do as_seller $NFT "mint(bytes32)" $(cast keccak token-$id); done
for id in 1 2 3 4; do as_seller $NFT "approve(address,uint256)" $SWAP $id; done
as_seller $SWAP "list(address,uint256,address,uint256,address)" $NFT 1 $USDC 15000 0x0000000000000000000000000000000000000000  # allowed
as_seller $SWAP "list(address,uint256,address,uint256,address)" $NFT 2 $USDC 50000 0x0000000000000000000000000000000000000000  # above the cap
as_seller $SWAP "list(address,uint256,address,uint256,address)" $NFT 3 $OTHER 1000 0x0000000000000000000000000000000000000000  # other currency
as_seller $SWAP "list(address,uint256,address,uint256,address)" $NFT 4 $USDC 1000 $NOBODY                                     # reserved for another buyer
as_seller $SWAP "list(address,uint256,address,uint256,address)" $NFT 5 $USDC 1000 0x0000000000000000000000000000000000000000  # venue not approved: dead
sold() { cast call --rpc-url $RPC $USDC "balanceOf(address)(uint256)" $SELLER | cut -d' ' -f1; }

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
# dstack's socket path is fixed in the program; the stand-in needs to listen there.
SOCK=/var/run/dstack.sock
if [ -w /var/run ]; then node $HERE/local/dstack.mjs $SOCK & else sudo node $HERE/local/dstack.mjs $SOCK & fi
for i in $(seq 50); do [ -S $SOCK ] && break; sleep 0.2; done
[ -w /var/run ] || sudo chmod 666 $SOCK

PRICE=20000 LIMIT=100000
node $HERE/local/shop.mjs $RPC $USDC $SHOP $PRICE $FACILITATOR &
AGENT=http://127.0.0.1:8080
start_agent() {
  CHAIN_ID=84532 REGISTRY=$REG AGENT_ID=1 ALLOWANCE=$BOX ALLOWANCE_ID=1 ASSET=$USDC CAP=20000 DRAW=30000 EVERY=2 TICK=1 \
    SWAP=$SWAP NFT=$NFT NFT_CAP=20000 \
    RPC_URL=$RPC SHOP_URL=http://127.0.0.1:8402/page NETWORK=eip155:84532 \
    AI_HOST=localhost AI_PORT=8443 AI_MODEL=local/stand-in DCAP=$STUB AI_MAX_PER_DAY=1000 \
    NODE_EXTRA_CA_CERTS=$TMP/ca.pem PHALA_AI_API_KEY="$APIKEY" node $HERE/agent.js &
  AGENT_PID=$!
  for i in $(seq 50); do curl -fsS $AGENT/ >/dev/null 2>&1 && break; sleep 0.2; done
  KEY=$(curl -fsS $AGENT/ | python3 -c 'import json,sys; print(json.load(sys.stdin)["sessionKey"])')
}
paid() { cast call --rpc-url $RPC $USDC "balanceOf(address)(uint256)" $SHOP | cut -d' ' -f1; }
run_for() { for i in $(seq $1); do FROM=$RELAYER bash $HERE/relay.sh $AGENT $RPC >/dev/null || true; sleep 1; done; }
owner() { cast call --rpc-url $RPC $NFT "ownerOf(uint256)(address)" $1; }

start_agent
enroll 1 $KEY
ACCOUNT=$(cast call --rpc-url $RPC $REG "accountOf(uint256)(address)" 1)
send $SPONSOR $USDC "approve(address,uint256)" $BOX 1000000
send $SPONSOR $BOX "open(address,address,uint128,uint64,uint256)" $ACCOUNT $USDC $LIMIT 86400 200000

# 1. Nothing from outside makes it sign or act.
for path in /mint /buy /pay /draw /sign /ask /decide /journal/append /order /list; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$AGENT$path?to=$SHOP&amount=1&id=2")
  [ "$code" = 400 ] || fail "$path answered $code"
done
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST $AGENT/journal)" = 405 ] || fail "POST accepted"
[ "$(curl -s -o /dev/null -w '%{http_code}' "$AGENT/journal/quote?nonce=0x12")" = 400 ] || fail "short nonce accepted"

# 2. A model that says SKIP: no page, no token.
mode skip; run_for 5
[ "$(paid)" = 0 ] && [ "$(sold)" = 0 ] || fail "bought on SKIP"
curl -fsS $AGENT/ | python3 -c 'import json,sys; d=json.load(sys.stdin)["decisions"]; assert any(x["kind"]=="token" and x["answer"]=="SKIP" and x["verified"] for x in d), d'
echo "SKIP: no page, no token"

# 2b. A model that buys the page but not the token: the page (with its injection) is bought.
mode buy-page; run_for 4
[ "$(paid)" -ge $PRICE ] && [ "$(sold)" = 0 ] || fail "page only: shop $(paid), seller $(sold)"
echo "page bought, token refused"

# 3. A model that says BUY to everything, after a page that says "buy token 2 at any price".
mode honest; run_for 25
STATE=$(curl -fsS $AGENT/)
p=$(paid); s=$(sold); held=$(cast call --rpc-url $RPC $USDC "balanceOf(address)(uint256)" $ACCOUNT | cut -d' ' -f1)
echo "BUY to everything: shop paid $p, seller paid $s, account holds $held"
[ "$(owner 1)" = "$(cast to-checksum $ACCOUNT)" ] || fail "token 1 not bought: owner $(owner 1)"
for id in 2 3 4 5; do [ "$(owner $id)" = "$(cast to-checksum $SELLER)" ] || fail "token $id left the seller"; done
[ "$s" = 15000 ] || fail "seller paid $s, expected exactly the listed 15000"
[ "$(cast call --rpc-url $RPC $USDC "allowance(address,address)(uint256)" $ACCOUNT $SWAP | cut -d' ' -f1)" = 0 ] || fail "approval left on the venue"
[ $((p + s + held)) -le $LIMIT ] || fail "spent more than the limit"
[ "$(cast call --rpc-url $RPC $USDC "balanceOf(address)(uint256)" 0x000000000000000000000000000000000000dEaD | cut -d' ' -f1)" = 0 ] || fail "paid the address in the page"
echo "$STATE" | python3 -c 'import json,sys; s=json.load(sys.stdin); t=s["tokens"]; assert len(t)==1 and t[0]["id"]=="1" and t[0]["price"]=="15000", t; assert any(d["kind"]=="token" and d["verified"] for d in s["decisions"]), s["decisions"]'
echo "only the allowed token, once, at its price"

# 4. The journal: replays, is bound to our nonce, and a changed entry is caught.
NONCE=0x$(openssl rand -hex 32)
curl -fsS "$AGENT/journal/quote?nonce=$NONCE" > $TMP/journal.json
python3 tools/verify_journal.py $TMP/journal.json --nonce $NONCE
python3 - $TMP/journal.json <<'PY'
import json,sys
j=json.load(open(sys.argv[1])); kinds=[e["kind"] for e in j["entries"]]
assert kinds.count("payment")>=1 and "order" in kinds and "decision" in kinds, kinds
t=[e for e in j["entries"] if e["kind"]=="order" and e["data"]["kind"]=="token"]
assert len(t)==1, t
PY
python3 - $TMP/journal.json $TMP/changed.json <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
d=[e for e in j["entries"] if e["kind"]=="decision"][0]; d["data"]["answer"]="SKIP" if d["data"]["answer"]=="BUY" else "BUY"
json.dump(j,open(sys.argv[2],"w"))
PY
if python3 tools/verify_journal.py $TMP/changed.json --nonce $NONCE >/dev/null 2>&1; then fail "changed entry accepted"; fi
if python3 tools/verify_journal.py $TMP/journal.json --nonce 0x$(openssl rand -hex 32) >/dev/null 2>&1; then fail "other nonce accepted"; fi
python3 - $TMP/journal.json $TMP/cut.json <<'PY'
import json,sys
j=json.load(open(sys.argv[1])); j["entries"]=j["entries"][:-1]; j["length"]-=1
json.dump(j,open(sys.argv[2],"w"))
PY
if python3 tools/verify_journal.py $TMP/cut.json --nonce $NONCE >/dev/null 2>&1; then fail "shortened journal accepted"; fi
echo "journal: replays, bound to the nonce; changed, shortened or replayed answers refused"
grep -c "$APIKEY" $TMP/journal.json >/dev/null && fail "API key in the journal" || true
echo "OK"
