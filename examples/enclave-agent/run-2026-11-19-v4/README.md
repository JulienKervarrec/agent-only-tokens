# Fourth program on a real machine, 19 November 2026

Study sections 3.30 and 3.31, and "Fourth program" in `../README.md`. Phala Cloud,
`tdx.small`, dstack OS 0.5.12, Phala KMS, our pre-launch script; Base Sepolia.

- `quote.hex`: the quote over the first enrollment of the agent's key.
- `quote-rotation.hex`: the quote of the new key after the machine was restarted.
- `rtmr3-events.txt`: the events dstack measured (after the restart; only the
  instance's keys differ from the first boot).

`SHA256SUMS` lists the hash of each file.

## What happened

| Step | Result |
| --- | --- |
| Compose hash shown by Phala Cloud before deploying, then measured by the machine | `4ae2d85a…7c1a`, the value computed on 18 November |
| Verifier approving exactly that code, announced, in force after 120 s | [`0xD850…987c`](https://sepolia.basescan.org/address/0xD850afBFFD888b289196ECA2C98a906cC615987c); Intel's check on chain: platform level 0 |
| Quote recorded, then the agent's key enrolled, no attester signature | 3,719,600 and 203,951 gas; account [`0xbb82…d44F`](https://sepolia.basescan.org/address/0xbb8202d84cC93F2bDb69170F6dFaf03Ee84fd44F) |
| Allowance opened by the sponsor | 1 test USDC deposited, at most 0.05 USDC a day |
| The agent signs, on its own, an order to draw 0.03; relayed by us | [tx](https://sepolia.basescan.org/tx/0xc5a7adea4e9e8f9195cc777fee6581ffdc7c0ed6b4af3056327620332bf6a2a0), 148,617 gas |
| Two purchases, 600 s apart, from `x402.org/protected` | 0.01 USDC each, HTTP 200, settled: [1](https://sepolia.basescan.org/tx/0x540f0536f9663cc2d4979cae8fb435a46cb85084aa1c309dc4ad0880542117fe), [2](https://sepolia.basescan.org/tx/0xbd795fb16f8a63c0ba18e5a21042fe0a2fd73f27c6ccfb9a228d0d1a79e1e74c) |
| Requests from outside | `POST` and `PUT` refused (405); `/sign`, `/pay`, `/order`, `/draw` refused (400); `/enroll` asked for another key still quotes the agent's own key |
| Machine restarted from Phala Cloud | New key, same compose hash; the program does nothing until its key is enrolled |
| New quote recorded, new key enrolled on the same account | 3,719,588 and 48,263 gas; the allowance still had 0.02 left: a new key does not reset the limit |
| Third purchase, with the new key | [tx](https://sepolia.basescan.org/tx/0xd2d8c39337554c0f51d9b1d21c1bfa0c398150f5da81d02bce290ca1d5728de7) |
| The agent signs an order to draw the 0.02 left; relayed | [tx](https://sepolia.basescan.org/tx/0x43e88b2541771239b9054259e3ba0ddab6decfe2ccc0dfbd96a5a88664e54a52); allowance at 0 for the day |
| One more unit, simulated | Refused: from the account `OverLimit(0)`, from the sponsor `NotAccount()` |
| Fourth and fifth purchases, then nothing | [4](https://sepolia.basescan.org/tx/0x3eedb0c803788171c25a6cc1ba621e5d2f5c128db1acd0e0c9cbb5ddabf39aad), [5](https://sepolia.basescan.org/tx/0x17cc1d5cc68a3b7eb526231121cf96d87b8d88c645385490996d1a65b93925ac); then the account was empty, the allowance at its limit, and the agent signed no further order for a whole period |

In all: 0.05 USDC drawn, the day's limit, and 0.05 spent in five x402
purchases. Session keys `0x296c9982735f6fb01ac0a8ba0ada12158a3c2be1`, then
`0x4a8d16825e0ece57bc1f057ee393a30d8caed896`.

**Notes.** Phala Cloud's deployment form changed on 19 November: the pre-launch
script is set in its new form, which shows the compose hash before deploying.
Its KMS was measured with a new value (`mr-kms`); the key provider is the same
as on 17 November. The public Base Sepolia node failed some calls; the program
reported it and tried again at the next tick.

**Limits.** We relayed the draw orders ourselves; anyone could have. One
machine, one day. The program decides by a fixed rule (step 3.3 adds a model).
