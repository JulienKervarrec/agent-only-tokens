#!/usr/bin/env bash
# Incident drill (docs/operations.md), run on a local chain with throwaway keys made here and
# never written down. Each step is one procedure of the runbook, and each is checked on chain:
#   1. a misbehaving agent: its sponsor freezes it, at once; its tokens stop moving
#   2. its money: the sponsor closes its allowance and takes the rest back
#   3. the attesters revoke it, for good
#   4. a faulty venue: the attesters remove it, at once
#   5. a suspicious verifier announced: the attesters halt enrollments, which cancels it
# Run from the repository root after `forge build`: bash examples/operations/drill.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
RPC=http://127.0.0.1:8546
fail() { echo "FAIL: $*"; exit 1; }
trap 'kill $(jobs -p) 2>/dev/null || true' EXIT
anvil --port 8546 --silent --disable-code-size-limit &
for i in $(seq 50); do cast chain-id --rpc-url $RPC >/dev/null 2>&1 && break; sleep 0.2; done
accts=($(cast rpc --rpc-url $RPC eth_accounts | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)))'))
DEPLOYER=${accts[0]} SPONSOR=${accts[1]} OTHER=${accts[2]}
send() { cast send --rpc-url $RPC --unlocked --from "$@" >/dev/null; }
view() { cast call --rpc-url $RPC "$@" | cut -d' ' -f1; }
create() { cast send --rpc-url $RPC --unlocked --from $DEPLOYER --create "$@" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])'; }
artifact() { python3 -c 'import json,sys; b=json.load(open(sys.argv[1]))["bytecode"]; print(b if isinstance(b,str) else b["object"])' "$1"; }
newkey() { cast wallet new --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["private_key"])'; }
A1=$(newkey) A2=$(newkey) A3=$(newkey) AGENT_KEY=$(newkey)
ATT="[$(cast wallet address $A1),$(cast wallet address $A2),$(cast wallet address $A3)]"
# Two attesters sign a digest; signatures sorted by signer address, as the registry expects.
sigs() {
  python3 - "$(cast wallet address $A1)" "$(cast wallet sign --no-hash $1 --private-key $A1)" "$(cast wallet address $A2)" "$(cast wallet sign --no-hash $1 --private-key $A2)" <<'PY'
import sys
a = [(sys.argv[1].lower(), sys.argv[2]), (sys.argv[3].lower(), sys.argv[4])]
print("[" + ",".join(s for _, s in sorted(a)) + "]")
PY
}
FAR=9999999999 EVID=$(cast keccak drill)
NOTICE=60
REG=$(create "$(artifact out/AttestedAgentRegistry.sol/AttestedAgentRegistry.json)$(cast abi-encode 'f(address[],uint256,uint256,uint64,uint64,address,address)' "$ATT" 2 0 86400 $NOTICE 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 | cut -c3-)")
KEY=$(cast wallet address $AGENT_KEY)
D=$(view $REG "hashAttestedEnrollment(uint256,address,bytes32,address,uint256,uint64)(bytes32)" 1 $KEY $EVID $SPONSOR 0 $FAR)
send $SPONSOR $REG "enroll(uint256,address,bytes32,uint64,bytes[])" 1 $KEY $EVID $FAR "$(sigs $D)"
ACCOUNT=$(view $REG "accountOf(uint256)(address)" 1)
# Setting: an agent-only collection, a venue in force, and an allowance in a plain token.
NFT=$(create "$(artifact out/Reference.t.sol/ReferenceCollection.json)$(cast abi-encode 'f(address)' $REG | cut -c3-)")
VENUE=$(create "$(artifact out/AgentSwap.sol/AgentSwap.json)")
D=$(view $REG "hashVenue(address,bool,bytes32,uint64)(bytes32)" $VENUE true $EVID $FAR)
send $OTHER $REG "setVenue(address,bool,bytes32,uint64,bytes[])" $VENUE true $EVID $FAR "$(sigs $D)"
cast rpc --rpc-url $RPC evm_increaseTime $((NOTICE + 1)) >/dev/null; cast rpc --rpc-url $RPC evm_mine >/dev/null
[ "$(view $REG "isVenue(address)(bool)" $VENUE)" = true ] || fail "venue not in force"
MONEY=$(create "$(artifact out/AgentOnly.t.sol/MockUSDC.json)")
BOX=$(create "$(artifact out/AgentAllowance.sol/AgentAllowance.json)")
send $SPONSOR $MONEY "mint(address,uint256)" $SPONSOR 1000
send $SPONSOR $MONEY "approve(address,uint256)" $BOX 1000
send $SPONSOR $BOX "open(address,address,uint128,uint64,uint256)" $ACCOUNT $MONEY 100 86400 1000
# The agent mints a token through its account (its key signs a relayed order; anyone relays).
act() { # target data -> the account executes it, signed by the agent's key, relayed by OTHER
  local nonce digest sig
  nonce=$(view $ACCOUNT "nonce()(uint256)")
  digest=$(view $ACCOUNT "execDigest(address,uint256,bytes,uint256,uint64)(bytes32)" $1 0 $2 $nonce $FAR)
  sig=$(cast wallet sign --no-hash $digest --private-key $AGENT_KEY)
  cast send --rpc-url $RPC --unlocked --from $OTHER $ACCOUNT "executeBySig(address,uint256,bytes,uint64,bytes)" $1 0 $2 $FAR $sig >/dev/null 2>&1
}
act $NFT "$(cast calldata 'mint()')" || fail "the agent could not mint"
act $NFT "$(cast calldata 'approve(address,uint256)' $VENUE 1)" || fail "the agent could not approve the venue"
act $BOX "$(cast calldata 'draw(uint256,uint256)' 1 40)" || fail "the agent could not draw"
# Control: before the freeze, the venue could take the token (simulated, nothing is sent).
cast rpc --rpc-url $RPC anvil_impersonateAccount $VENUE >/dev/null
cast call --rpc-url $RPC --from $VENUE $NFT "transferFrom(address,address,uint256)" $ACCOUNT $VENUE 1 >/dev/null 2>&1 \
  || fail "control: the venue could not take the token even before the freeze"
cast rpc --rpc-url $RPC anvil_stopImpersonatingAccount $VENUE >/dev/null
echo "setting: agent 1 holds token 1, approved to a venue in force; its allowance holds 960"

# 1. Freeze: one transaction by the sponsor, no signature needed, effective at once.
send $SPONSOR $REG "setFrozen(uint256,bool)" 1 true
[ "$(view $REG "isAgent(address)(bool)" $ACCOUNT)" = false ] || fail "still an agent after the freeze"
act $NFT "$(cast calldata 'burn(uint256)' 1)" && fail "a frozen agent acted"
# The venue itself tries to take the token it was approved for (the local chain lets us act as it).
cast rpc --rpc-url $RPC anvil_impersonateAccount $VENUE >/dev/null
cast rpc --rpc-url $RPC anvil_setBalance $VENUE 0xDE0B6B3A7640000 >/dev/null
cast call --rpc-url $RPC --from $VENUE $NFT "transferFrom(address,address,uint256)" $ACCOUNT $VENUE 1 >/dev/null 2>&1 \
  && fail "the venue could move a frozen agent's token"
cast rpc --rpc-url $RPC anvil_setBalance $VENUE 0x0 >/dev/null
cast rpc --rpc-url $RPC anvil_stopImpersonatingAccount $VENUE >/dev/null
echo "1. frozen by its sponsor in one transaction: no longer an agent; it cannot act, its token does not move"

# 2. Close the allowance: the sponsor takes the rest back; nothing more can be drawn.
send $SPONSOR $BOX "close(uint256)" 1
[ "$(view $MONEY "balanceOf(address)(uint256)" $SPONSOR)" = 960 ] || fail "the rest did not come back"
[ "$(view $BOX "available(uint256)(uint256)" 1)" = 0 ] || fail "something can still be drawn"
echo "2. allowance closed by its sponsor: 960 back; the agent keeps only the 40 it drew"

# 3. Revoke: two attesters, effective at once and for good.
D=$(view $REG "hashRevocation(uint256,uint64)(bytes32)" 1 $FAR)
send $OTHER $REG "revoke(uint256,uint64,bytes[])" 1 $FAR "$(sigs $D)"
send $SPONSOR $REG "setFrozen(uint256,bool)" 1 false
[ "$(view $REG "isAgent(address)(bool)" $ACCOUNT)" = false ] || fail "a revoked agent came back"
echo "3. revoked by two attesters: unfreezing does not bring it back"

# 4. Remove the venue: two attesters, effective at once.
D=$(view $REG "hashVenue(address,bool,bytes32,uint64)(bytes32)" $VENUE false $EVID $FAR)
send $OTHER $REG "setVenue(address,bool,bytes32,uint64,bytes[])" $VENUE false $EVID $FAR "$(sigs $D)"
[ "$(view $REG "isVenue(address)(bool)" $VENUE)" = false ] || fail "the venue is still in force"
echo "4. venue removed by two attesters, at once"

# 5. A verifier announced that should not be: halting cancels the announcement, at once.
FAKE=$VENUE # any contract will do: the point is the announcement
D=$(view $REG "hashVerifier(address,bytes32,uint64)(bytes32)" $FAKE $EVID $FAR)
send $OTHER $REG "setEnrollmentVerifier(address,bytes32,uint64,bytes[])" $FAKE $EVID $FAR "$(sigs $D)"
lower() { tr '[:upper:]' '[:lower:]'; }
[ "$(view $REG "announcedVerifier()(address)" | lower)" = "$(echo $FAKE | lower)" ] || fail "no announcement"
D=$(view $REG "hashHalt(bytes32,uint64)(bytes32)" $EVID $FAR)
send $OTHER $REG "haltEnrollments(bytes32,uint64,bytes[])" $EVID $FAR "$(sigs $D)"
[ "$(view $REG "announcedVerifier()(address)")" = 0x0000000000000000000000000000000000000000 ] || fail "the announcement survived the halt"
[ "$(view $REG "enrollmentHalted()(bool)")" = true ] || fail "enrollments not halted"
K2=$(cast wallet address $(newkey))
D=$(view $REG "hashAttestedEnrollment(uint256,address,bytes32,address,uint256,uint64)(bytes32)" 2 $K2 $EVID $SPONSOR 0 $FAR)
cast send --rpc-url $RPC --unlocked --from $SPONSOR $REG "enroll(uint256,address,bytes32,uint64,bytes[])" 2 $K2 $EVID $FAR "$(sigs $D)" >/dev/null 2>&1 \
  && fail "an enrollment went through a halt"
echo "5. a verifier announced by mistake: halted by two attesters, the announcement is gone and no enrollment passes"
echo OK
