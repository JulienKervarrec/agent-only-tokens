# Fifth program on a real machine, 19 November 2026

Step 3.3; "Fifth program" in `../README.md`. Phala Cloud, `tdx.small`, dstack OS 0.5.15
(0.5.12 was no longer offered), Phala KMS, our pre-launch script; Base Sepolia. The gateway's
API key was given to the machine as an encrypted secret; the manifest only names it.

- `quote.hex`: the quote over the enrollment of the agent's key.

`SHA256SUMS` lists the hash of each file.

## What happened

| Step | Result |
| --- | --- |
| Compose hash shown by Phala Cloud before deploying, then measured by the machine | `fb6c9d29…263f`, the value computed in advance, with `allowed_envs: ["PHALA_AI_API_KEY"]` |
| Verifier approving exactly that code, announced, in force after 120 s | [`0xa071…0609`](https://sepolia.basescan.org/address/0xa071a904CC60f36a67aD73167838d49A092A0609); Intel's check on chain: platform level 0 |
| Quote recorded, key enrolled with no attester signature | 3,719,552 and 203,951 gas; account [`0x8c11…70Dc`](https://sepolia.basescan.org/address/0x8c116e8670b650d3A1e281c5f058f419F5c370Dc) |
| Allowance 2 opened by the sponsor | 1 test USDC, at most 0.05 USDC a day |
| The agent signs a draw of 0.03 on its own; relayed by us | [tx](https://sepolia.basescan.org/tx/0x28aa81a6efc7016f9159b70fc388049b368b18a6b1cb50be6a40a6a06b0bd410) |
| Gateway checked inside the machine | Report bound to the agent's nonce; quote genuine and up to date by Automata's verifier (read-only call); keyset `sha256:31bf…a1b0`, gateway compose `04d79a23…6085`, commit `8d0018f8` |
| Decision 1 | `SKIP`, receipt `rcpt-c00ba4cf6337cde186ebe789` verified: no purchase |
| Decision 2 | `BUY`, receipt `rcpt-09ebbf90ed6fa64e84e6bfb8` verified: one purchase of 0.01 from `x402.org/protected`, HTTP 200, settled ([tx](https://sepolia.basescan.org/tx/0x0ebd06f48281c625ef2e3ac2b1de18a1760cff8b085467391680f0223598e8b7)) |
| Decision 3 | `SKIP`, receipt `rcpt-6efef41b8b063918594dd0dc` verified: no purchase |
| Requests from outside | `POST /` refused (405); `/ask`, `/decide`, `/buy`, `/sign`, `/draw` refused (400); the state never shows the API key |

Session key `0x29bf73ed1cd6e5da7b6b3e4817088ed64a5e7393`. The machine ran about 35 minutes,
then was deleted; Phala balance 3.20 before, 3.18 after (machine and model together).

**Limits.** Three questions on one machine. Inside the machine, the gateway's quote check relies
on the Base Sepolia node's answer to a read-only call. The gateway's own code is recorded, not
pinned. The model sees only the price, the balances and the page address.
