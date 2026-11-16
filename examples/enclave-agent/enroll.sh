#!/bin/bash
# Enrolls an enclave agent by hardware attestation on Base Sepolia.
# Inputs, in the current directory: quote.hex (the quote returned by the agent's /enroll),
# event-digests.hex (the 48-byte digests of its RTMR3 events, concatenated).
# Environment: DEPLOYER_KEY, ATTESTER1..3 (throwaway test keys), ETH_RPC_URL, REPO (this repository),
# SESSION_KEY, COMPOSE_HASH, COMPOSE_INDEX, DEADLINE, and the registry address the quote was made for.
set -euo pipefail
DCAP=0xaDdeC7e85c2182202b66E331f2a4A0bBB2cEEa1F   # Automata DCAP Attestation, Base Sepolia
ME=$(cast wallet address $DEPLOYER_KEY)
QUOTE=$(cat quote.hex); DIGESTS=$(cat event-digests.hex)

# 1. What the real verifier says about the quote (a call, nothing is sent).
OUT=$(cast call $DCAP "verifyAndAttestOnChain(bytes)(bool,bytes)" $QUOTE --gas-limit 30000000 | sed -n 2p)
TCB=$((16#${OUT:10:2}))
IMAGE=$(cast keccak 0x${OUT:$((2 + 2*(11+120))):704})          # attributes .. RTMR2 of the report body
CODE=$(cast keccak $(cast abi-encode "f(bytes32,bytes32)" $IMAGE $COMPOSE_HASH))
echo "platform level: $TCB   base image: $IMAGE   code: $CODE"
[ "$TCB" = "0" ] || { echo "platform not up to date"; exit 1; }

# 2. Verifier accepting up-to-date platforms and this code only, then a registry that requires it.
create() { local c=$1; shift; (cd $REPO && forge create $c --private-key $DEPLOYER_KEY --broadcast --constructor-args "$@") | grep "Deployed to" | awk '{print $3}'; }
VERIFIER=$(create src/experimental/DstackEnrollmentVerifier.sol:DstackEnrollmentVerifier $DCAP 1 "[$CODE]")
ATT="[$(cast wallet address $ATTESTER1),$(cast wallet address $ATTESTER2),$(cast wallet address $ATTESTER3)]"
REG=$(create src/AttestedAgentRegistry.sol:AttestedAgentRegistry "$ATT" 2 100000000000000 2592000 0x0000000000000000000000000000000000000000 $VERIFIER)
echo "verifier: $VERIFIER"; echo "registry: $REG"
[ "${REG,,}" = "${REGISTRY,,}" ] || { echo "registry address differs from the one in the quote"; exit 1; }

# 3. The quote is verified on chain, then the registry enrolls the key it carries. No attester signs.
cast send $VERIFIER "attest(bytes,bytes,uint256,bool,bytes32)" $QUOTE $DIGESTS $COMPOSE_INDEX false $COMPOSE_HASH --private-key $DEPLOYER_KEY --gas-limit 12000000 --json | python3 -c "import sys,json;r=json.load(sys.stdin);print('attest tx',r['transactionHash'],'status',r['status'],'gas',int(r['gasUsed'],16))"
cast send $REG "enroll(uint256,address,bytes32,uint64,bytes[])" 1 $SESSION_KEY $COMPOSE_HASH $DEADLINE "[]" --value 100000000000000 --private-key $DEPLOYER_KEY --json | python3 -c "import sys,json;r=json.load(sys.stdin);print('enroll tx',r['transactionHash'],'status',r['status'],'gas',int(r['gasUsed'],16))"
ACC=$(cast call $REG "accountOf(uint256)(address)" 1)
echo "agent account: $ACC   key: $(cast call $REG 'keyOf(uint256)(address)' 1)   isAgent: $(cast call $REG 'isAgent(address)(bool)' $ACC)"
