#!/usr/bin/env python3
"""Writes v5/docker-compose.yml: the fifth program inlined, with its settings written literally,
so that the compose hash dstack measures covers both. Settings are those of the Base Sepolia run.

    python3 v5/make_compose.py

The gateway's API key is not a setting: Phala Cloud gives it to the machine encrypted, and the
manifest only names it (allowed_envs).
"""
import pathlib

here = pathlib.Path(__file__).parent
SETTINGS = {
    "CHAIN_ID": "84532",
    "REGISTRY": "0x2ed6c67ccFA6F58DE8fea70b0D9c7b01b9c57941",  # deployments: fifth program run
    "AGENT_ID": "1",
    "ALLOWANCE": "0x72E92d7bb95425cf59f7F967b698DBFbBa8c6ACf",
    "ALLOWANCE_ID": "2",
    "ASSET": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",  # USDC on Base Sepolia
    "CAP": "20000",  # 0.02 USDC at most per purchase
    "DRAW": "30000",  # 0.03 USDC asked from the allowance when short
    "EVERY": "300",  # at most one question, hence one purchase, per 5 minutes
    "TICK": "15",
    "RPC_URL": "https://sepolia.base.org",
    "SHOP_URL": "https://x402.org/protected",
    "NETWORK": "eip155:84532",
    "AI_HOST": "inference.phala.com",  # Phala's confidential AI gateway
    "AI_PORT": "443",
    "AI_MODEL": "openai/gpt-oss-120b",
    "DCAP": "0xaDdeC7e85c2182202b66E331f2a4A0bBB2cEEa1F",  # Automata DCAP attestation, Base Sepolia
    "AI_MAX_PER_DAY": "100",
}
program = (here / "agent.js").read_text()
lines = [
    "# Agent-Only Tokens: the fifth agent program for dstack (Intel TDX), step 3.3.",
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
lines += ['      PHALA_AI_API_KEY: "${PHALA_AI_API_KEY}"']
lines += ["    command:", "      - node", "      - -e", "      - |"]
lines += [("        " + l) if l else "" for l in program.splitlines()]
(here / "docker-compose.yml").write_text("\n".join(lines) + "\n")
print("written", here / "docker-compose.yml")
