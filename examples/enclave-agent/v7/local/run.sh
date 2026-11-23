#!/usr/bin/env bash
# Local end-to-end test of the seventh program (the token as a pass), on a local chain, with
# nothing from Base Sepolia: the setting of the sixth program's test (Circle's USDC code, our
# registry, AgentAllowance, AgentSwap, a collection of the standard, a selling agent, the stand-in
# gateway, DCAP stub and dstack socket), and a shop that serves its page for a payment, or for
# free to an account that signs in (x402 extension sign-in-with-x) and holds a token of the
# collection. The page's payments go to the account of a third agent (an agent that sells).
# It checks that the agent pays while it holds no token, buys one from another agent, then signs
# in and pays no more; that another agent holding tokens is served and one holding none is not,
# nor a plain key; that a sign-in cannot be replayed; that the agent signs no challenge made for
# another site, with another statement, or without an expiry; and that nothing from outside makes
# it sign. When `npm ci` was run in examples/x402, each sign-in must also be accepted by the
# reference implementation of the extension.
# Throwaway keys, made here and never written down.
# Run from the repository root after `forge build`: bash examples/enclave-agent/v7/local/run.sh
set -euo pipefail
cd "$(dirname "$0")/../../../.."
RPC=http://127.0.0.1:8545
HERE=examples/enclave-agent/v7
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
REG=$(create "$(artifact out/AttestedAgentRegistry.sol/AttestedAgentRegistry.json)$(cast abi-encode 'f(address[],uint256,uint256,uint64,uint64,address,address)' "$ATT" 2 0 86400 2 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 | cut -c3-)")
BOX=$(create "$(artifact out/AgentAllowance.sol/AgentAllowance.json)")

# The collection and the second currency live in script/SepoliaDemo.s.sol, which `forge test` does not build.
[ -f out/SepoliaDemo.s.sol/TestUSD.json ] || forge build script/SepoliaDemo.s.sol >/dev/null
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
# A 2 s notice, waited for real: the chain keeps the clock of this machine, which the orders' deadlines need.
sleep 3; cast rpc --rpc-url $RPC evm_mine >/dev/null
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
# A socket left by an earlier test would be taken for the new one: remove it first.
if [ -w /var/run ]; then rm -f $SOCK; else sudo rm -f $SOCK; fi
if [ -w /var/run ]; then node $HERE/local/dstack.mjs $SOCK & else sudo "$(command -v node)" $HERE/local/dstack.mjs $SOCK & fi
for i in $(seq 50); do [ -S $SOCK ] && break; sleep 0.2; done
[ -w /var/run ] || sudo chmod 666 $SOCK

# The agent that sells the page (agent 3): the shop's payments go to its account.
S3=$(cast wallet new --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["private_key"])')
enroll 3 $(cast wallet address $S3)
SHOPACC=$(cast call --rpc-url $RPC $REG "accountOf(uint256)(address)" 3)
[ "$(cast call --rpc-url $RPC $REG "isAgent(address)(bool)" $SHOPACC)" = true ] || fail "the shop's account is not an agent"

PRICE=20000 LIMIT=200000
STATEMENT="Free access for the holder of a pass token."
node $HERE/local/shop.mjs $RPC $USDC $SHOPACC $PRICE $FACILITATOR $NFT "$STATEMENT" &
AGENT=http://127.0.0.1:8080
start_agent() {
  CHAIN_ID=84532 REGISTRY=$REG AGENT_ID=1 ALLOWANCE=$BOX ALLOWANCE_ID=1 ASSET=$USDC CAP=20000 DRAW=30000 EVERY=2 TICK=1 \
    SWAP=$SWAP NFT=$NFT NFT_CAP=20000 ORDER_TTL=60 PASS_STATEMENT="$STATEMENT" \
    RPC_URL=$RPC SHOP_URL=http://127.0.0.1:8402/page NETWORK=eip155:84532 \
    AI_HOST=localhost AI_PORT=8443 AI_MODEL=local/stand-in DCAP=$STUB AI_MAX_PER_DAY=1000 \
    NODE_EXTRA_CA_CERTS=$TMP/ca.pem PHALA_AI_API_KEY="$APIKEY" node $HERE/agent.js &
  AGENT_PID=$!
  for i in $(seq 50); do curl -fsS $AGENT/ >/dev/null 2>&1 && break; sleep 0.2; done
  KEY=$(curl -fsS $AGENT/ | python3 -c 'import json,sys; print(json.load(sys.stdin)["sessionKey"])')
}
paid() { cast call --rpc-url $RPC $USDC "balanceOf(address)(uint256)" $SHOPACC | cut -d' ' -f1; }
stat() { curl -fsS http://127.0.0.1:8403/ | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }
shopmode() { curl -fsS -X POST "http://127.0.0.1:8403/mode?to=$1" >/dev/null; }
run_for() { for i in $(seq $1); do FROM=$RELAYER bash $HERE/relay.sh $AGENT $RPC >/dev/null || true; sleep 1; done; }
owner() { cast call --rpc-url $RPC $NFT "ownerOf(uint256)(address)" $1; }
journal_has() { curl -fsS $AGENT/journal | python3 -c "import json,sys; e=json.load(sys.stdin)['entries']; print(sum(1 for x in e if x['kind']=='$1'))"; }

start_agent
enroll 1 $KEY
ACCOUNT=$(cast call --rpc-url $RPC $REG "accountOf(uint256)(address)" 1)
send $SPONSOR $USDC "approve(address,uint256)" $BOX 1000000
send $SPONSOR $BOX "open(address,address,uint128,uint64,uint256)" $ACCOUNT $USDC $LIMIT 86400 200000
echo "reference implementation of sign-in-with-x installed: $(stat reference)"

# 1. Nothing from outside makes it sign or act.
for path in /mint /buy /pay /draw /sign /signin /login /ask /decide /journal/append /order /list; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$AGENT$path?to=$SHOP&amount=1&id=2&domain=shop.example")
  [ "$code" = 400 ] || fail "$path answered $code"
done
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST $AGENT/journal)" = 405 ] || fail "POST accepted"

# 2. No token yet: the agent pays for the page (a model that buys the page, not the token).
mode buy-page; run_for 5
[ "$(paid)" -ge $PRICE ] && [ "$(sold)" = 0 ] || fail "page only: shop $(paid), seller $(sold)"
[ "$(stat free)" = 0 ] && [ "$(journal_has sign-in)" = 0 ] || fail "signed in without a token"
echo "no token: the page is paid, to an agent's account ($(paid))"

# 3. A model that says BUY to everything: the agent buys token 1 from the selling agent, then
# signs in and pays no more.
mode honest
for i in $(seq 40); do [ "$(owner 1)" = "$(cast to-checksum $ACCOUNT)" ] && break; FROM=$RELAYER bash $HERE/relay.sh $AGENT $RPC >/dev/null || true; sleep 1; done
[ "$(owner 1)" = "$(cast to-checksum $ACCOUNT)" ] || fail "token 1 not bought: owner $(owner 1)"
sleep 3; before=$(paid); free0=$(stat free)
run_for 10
[ "$(paid)" = "$before" ] || fail "paid again while holding the pass: $before then $(paid)"
[ "$(stat free)" -ge $((free0 + 2)) ] || fail "not served for free: $(stat free) visits"
[ "$(stat refused)" = 0 ] || fail "a sign-in of the agent was refused: $(stat lastRefusal)"
curl -fsS $AGENT/ | python3 -c 'import json,sys; s=json.load(sys.stdin); v=s["visits"]; assert v and all(x["free"] and x["served"] for x in v), v'
# Each sign-in is in the journal before it is sent, and its outcome after (one may be in flight).
curl -fsS $AGENT/journal | python3 -c 'import json,sys; e=json.load(sys.stdin)["entries"]; a=[x["data"]["nonce"] for x in e if x["kind"]=="sign-in"]; b=[x["data"]["nonce"] for x in e if x["kind"]=="sign-in-result" and x["data"]["served"]]; assert len(a)>=2 and b==a[:len(b)] and len(a)-len(b)<=1, (a,b)'
for id in 2 3 4 5; do [ "$(owner $id)" = "$(cast to-checksum $SELLER)" ] || fail "token $id left the seller"; done
echo "token bought from another agent, then $(stat free) free visits and no further payment"

# 4. A sign-in cannot be replayed.
REPLAY=$(stat lastSignIn)
[ "$(curl -s -o /dev/null -w '%{http_code}' -H "SIGN-IN-WITH-X: $REPLAY" http://127.0.0.1:8402/page)" = 402 ] || fail "replayed sign-in served"
[ "$(stat lastRefusal)" = "nonce unknown or already used" ] || fail "replay refused for another reason: $(stat lastRefusal)"

# 5. Other callers. The selling agent's account holds tokens: served. The shop's own agent holds
# none: refused. A plain key holds none and can hold none: refused.
signin() { # $1: 'account' or 'key', $2 private key, $3 address that signs in; prints the HTTP code
  local ask info msg hash sig header
  ask=$(curl -s -D - -o /dev/null http://127.0.0.1:${PORT:-8402}/page | tr -d '\r' | awk 'tolower($1)=="payment-required:" {print $2}')
  info=$(python3 -c 'import base64,json,sys; print(json.dumps(json.loads(base64.b64decode(sys.argv[1]))["extensions"]["sign-in-with-x"]["info"]))' "$ask")
  msg=$(python3 -c 'import json,sys; i=json.loads(sys.argv[1]); print(i["domain"]+" wants you to sign in with your Ethereum account:\n"+sys.argv[2]+"\n\n"+i["statement"]+"\n\nURI: "+i["uri"]+"\nVersion: 1\nChain ID: 84532\nNonce: "+i["nonce"]+"\nIssued At: "+i["issuedAt"]+"\nExpiration Time: "+i["expirationTime"], end="")' "$info" "$3")
  if [ "$1" = account ]; then
    hash=$(cast hash-message "$msg")
    sig=$(cast wallet sign --no-hash $(cast call --rpc-url $RPC $3 "messageDigest(bytes32)(bytes32)" $hash) --private-key $2)
  else
    sig=$(cast wallet sign "$msg" --private-key $2)
  fi
  header=$(python3 -c 'import base64,json,sys; i=json.loads(sys.argv[1]); i.update(address=sys.argv[2],chainId="eip155:84532",type="eip191",signature=sys.argv[3]); print(base64.b64encode(json.dumps(i).encode()).decode())' "$info" "$3" "$sig")
  curl -s -o $TMP/signin.body -w '%{http_code}' -H "SIGN-IN-WITH-X: $header" http://127.0.0.1:${PORT:-8402}/page
}
# (The agent keeps visiting meanwhile, so the shop's counters move on their own: the answer
# to each request is what is checked.)
[ "$(signin account $S2 $(cast to-checksum $SELLER))" = 200 ] && grep -q "free for the holder $(cast to-checksum $SELLER)" $TMP/signin.body || fail "an agent holding tokens was not served: $(stat lastRefusal)"
[ "$(signin account $S3 $(cast to-checksum $SHOPACC))" = 402 ] && [ "$(stat lastRefusal)" = "holds no token" ] || fail "an agent holding no token: $(stat lastRefusal)"
STRANGER=$(cast wallet new --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["private_key"])')
[ "$(signin key $STRANGER $(cast wallet address $STRANGER))" = 402 ] && [ "$(stat lastRefusal)" = "holds no token" ] || fail "a plain key: $(stat lastRefusal)"
echo "another holder served; an agent without a token and a plain key refused; replay refused"

# 5b. The holder-only service of the real run (v7/shop.js, no payment offered), on this chain.
RPC_URL=$RPC NFT=$NFT CHAIN_ID=84532 ORIGIN=http://127.0.0.1:8402 STATEMENT="$STATEMENT" node -e "$(sed 's/listen(8402)/listen(8502)/' $HERE/shop.js)" &
sleep 1
real() { curl -fsS http://127.0.0.1:8502/stats | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }
[ "$(PORT=8502 signin account $S2 $(cast to-checksum $SELLER))" = 200 ] && grep -q "free for the holder $(cast to-checksum $SELLER)" $TMP/signin.body || fail "holder service: holder not served: $(real lastRefusal)"
[ "$(PORT=8502 signin account $S3 $(cast to-checksum $SHOPACC))" = 402 ] && [ "$(real lastRefusal)" = "holds no token" ] || fail "holder service: $(real lastRefusal)"
[ "$(PORT=8502 signin key $STRANGER $(cast wallet address $STRANGER))" = 402 ] && [ "$(real lastRefusal)" = "signature refused by the account" ] || fail "holder service, plain key: $(real lastRefusal)"
[ "$(curl -s -o /dev/null -w '%{http_code}' -H "SIGN-IN-WITH-X: $(real lastSignIn)" http://127.0.0.1:8502/page)" = 402 ] && [ "$(real lastRefusal)" = "nonce unknown or already used" ] || fail "holder service: replay"
echo "holder-only service of the real run: holder served; no token, plain key and replay refused"

# 6. Challenges the agent does not sign: for another site, with another statement, without an
# expiry. It signs nothing and, the model saying BUY, pays instead.
for m in other-domain other-statement no-expiry; do
  shopmode $m; n=$(journal_has sign-in); p=$(paid)
  for i in $(seq 12); do [ "$(paid)" -gt "$p" ] && break; FROM=$RELAYER bash $HERE/relay.sh $AGENT $RPC >/dev/null || true; sleep 1; done
  [ "$(journal_has sign-in)" = "$n" ] || fail "signed a challenge in mode $m"
  [ "$(paid)" -gt "$p" ] || fail "mode $m: neither signed in nor paid"
done
shopmode normal
echo "challenges for another site, with another statement or without expiry: not signed"

# 7. The journal replays and is bound to our nonce; spending stayed within the allowance.
NONCE=0x$(openssl rand -hex 32)
curl -fsS "$AGENT/journal/quote?nonce=$NONCE" > $TMP/journal.json
python3 tools/verify_journal.py $TMP/journal.json --nonce $NONCE
held=$(cast call --rpc-url $RPC $USDC "balanceOf(address)(uint256)" $ACCOUNT | cut -d' ' -f1)
[ $(( $(paid) + $(sold) + held )) -le $LIMIT ] || fail "spent more than the limit"
[ "$(cast call --rpc-url $RPC $USDC "balanceOf(address)(uint256)" 0x000000000000000000000000000000000000dEaD | cut -d' ' -f1)" = 0 ] || fail "paid the address in the page"
grep -c "$APIKEY" $TMP/journal.json >/dev/null && fail "API key in the journal" || true
echo "OK"
