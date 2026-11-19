#!/usr/bin/env python3
"""Writes v4/docker-compose.yml: the fourth program inlined, with its settings written literally,
so that the compose hash dstack measures covers both. Settings are those of the Base Sepolia run.

    python3 v4/make_compose.py
"""
import pathlib

here = pathlib.Path(__file__).parent
SETTINGS = {
    "CHAIN_ID": "84532",
    "REGISTRY": "0x3cA87b940194A38BB577f0A5a3089b67cf3af609",  # deployments: fourth program run
    "AGENT_ID": "1",
    "ALLOWANCE": "0x72E92d7bb95425cf59f7F967b698DBFbBa8c6ACf",
    "ALLOWANCE_ID": "1",
    "ASSET": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",  # USDC on Base Sepolia
    "CAP": "20000",  # 0.02 USDC at most per purchase
    "DRAW": "30000",  # 0.03 USDC asked from the allowance when short
    "EVERY": "600",  # at most one purchase per 10 minutes
    "TICK": "15",
    "RPC_URL": "https://sepolia.base.org",
    "SHOP_URL": "https://x402.org/protected",
    "NETWORK": "eip155:84532",
}
program = (here / "agent.js").read_text()
lines = [
    "# Agent-Only Tokens: the fourth agent program for dstack (Intel TDX), step 3.2.",
    "# The program and its settings are in this file, so the compose hash measured by dstack covers both.",
    "services:",
    "  agent:",
    "    image: node:22-alpine@sha256:1314fb30ec37592d5845e5a160d522c0e680972aa534549940b8d73bde88481a",
    "    read_only: true",
    '    restart: "no"',
    "    ports:",
    '      - "8080:8080"',
    "    volumes:",
    "      - /var/run/dstack.sock:/var/run/dstack.sock",
    "    environment:",
]
lines += [f'      {k}: "{v}"' for k, v in SETTINGS.items()]
lines += ["    command:", "      - node", "      - -e", "      - |"]
lines += [("        " + l) if l else "" for l in program.splitlines()]
(here / "docker-compose.yml").write_text("\n".join(lines) + "\n")
print("written", here / "docker-compose.yml")
