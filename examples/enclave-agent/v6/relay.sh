#!/usr/bin/env bash
# Relays the order the agent has signed, if any (a draw, or the purchase of a token): reads GET / of the agent and submits the
# order with executeBySig. The relayer pays the gas and can change nothing in the order.
# Usage: relay.sh AGENT_URL RPC_URL, with either PRIVATE_KEY (never printed) or FROM (an unlocked
# account of a local test chain) in the environment.
set -euo pipefail
agent=$1 rpc=$2
order=$(curl -fsS "$agent/" | python3 -c 'import json,sys; o=json.load(sys.stdin).get("order"); print("" if not o else " ".join([o["account"],o["target"],o["value"],o["data"],o["deadline"],o["signature"]]))')
[ -z "$order" ] && { echo "no order"; exit 0; }
set -- $order
if [ -n "${PRIVATE_KEY:-}" ]; then auth=(--private-key "$PRIVATE_KEY"); else auth=(--unlocked --from "$FROM"); fi
cast send --rpc-url "$rpc" "${auth[@]}" "$1" "executeBySig(address,uint256,bytes,uint64,bytes)" "$2" "$3" "$4" "$5" "$6" >/dev/null
echo "relayed an order for $1"
