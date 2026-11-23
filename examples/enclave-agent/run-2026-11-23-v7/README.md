# Seventh program on a real machine, 23 November 2026

One Phala Cloud machine (dstack 0.5.15, `tdx.small`, our pre-launch script) running
`docker-compose.yml` of this folder (the seventh program as released in v0.5.2; the one in
`v7/` was corrected after an independent review, study section 3.45): the agent and, beside
it, the holder-only service. About 13 minutes, about 0.01 $ of credit, then deleted. The key given to the
machine for the model gateway was a placeholder: this run asks the model nothing.

On Base Sepolia (all in `deployments/base-sepolia.json`): the registry, collection and account
of the sixth run. The agent's account holds token 1 of the collection since 19 November.

## The run

Compose hash `15b554c483cd4bf4b281a8cec2c48bbcee398bd7a5000a45a3bc21b13e962f35`, shown by Phala
Cloud before deployment and equal to the one computed beforehand
(`python3 ../manifest/compose-hash.py docker-compose.yml ../manifest/prelaunch-ours.sh --allow PHALA_AI_API_KEY`).

Its enrollment quote (`quote-enroll.hex`): genuine, platform up to date. A verifier approving
exactly that code (`0x923E0A98C627fC7F3B7f959E13dA7d5F8680e0e2`), announced with the 120 s
notice, then the key enrolled for agent 1 with no attester signature (transaction
`0x064321c13677e42ad337b497076a10fcbbaf6d0fd1fffb7c458d1f138bbec274`, block 62569953).

Within a minute the agent asked its shop for the page, was offered `sign-in-with-x`, signed in
with a message of its account, and was served. Five minutes later, again. It paid nothing and
signed no order: the account's balance stayed at 0.01 USDC.

- `sign-in-header.txt` is the first `SIGN-IN-WITH-X` header, as the shop then showed it on
  its public counters (it now shows a hash only). Given to the
  reference implementation one minute after it was made
  (`node ../../x402/siwx-verify.mjs https://sepolia.base.org 84532 http://shop:8402 "$(cat sign-in-header.txt)"`),
  the answer was `{"valid":true,"payer":"0xf0DA9912D2ef3Ae929667E85EEa4695A277Cc8af"}`. It
  cannot be checked again: a sign-in expires after five minutes (the answer is now
  `invalid_siwx_expired`), and its signature was checked on chain against a session key that
  was replaced the same day.
- The same header sent again from outside: refused (`nonce unknown or already used`).
- A fresh plain key answering a fresh challenge: refused (`signature refused by the account`).

`journal.json` is its journal, answered to our nonce `0x2ae3f096…7fa4`: four entries (two
sign-ins, two outcomes).

    python3 ../../../tools/verify_journal.py journal.json --nonce 0x2ae3f096905f15da0f2411cfa9c8596cf99c53cee544957eabbf992e5a2b7fa4

With `--rpc`, `--dcap`, `--compose-hash` and `--verifier` it also said, that day: quote genuine
(level 0), production machine, program `15b554c4…2f35`, code approved by the verifier above.
Of the machine's answer the file keeps the head, the length, the nonce, the quote and the
entries; its event log, session key and report data were not kept.

## The same program on dstack OS 0.6.4

A second machine, the same compose file and pre-launch script, with the system Phala Cloud now
offers by default. About 8 minutes, then deleted. Recorded in `probe-os064.json` and
`probe-os064-enroll.hex` (its enrollment quote; not named `quote…` because the nightly check
compares those with the 0.5 images only).

- The manifest is version 3 (three more fields, the version as a string): compose hash
  `66dfe96ab4493d8f81c21567f409b4bca40502907adf9f5472196d503a34b513`, shown by Phala Cloud and
  reproduced by `compose-hash.py docker-compose.yml ../manifest/prelaunch-ours.sh --allow PHALA_AI_API_KEY --v3 <key provider id>`.
- `MRCONFIGID` in the quote is `03` followed by 32 bytes
  (`0a2872d7caef138cec80c3e49f6cbd6abe95994a00ce1e624bd1066e42430147`): format 3, the hash of a
  document naming the application, the compose hash, the instance and the key provider. Reproduced
  since (study section 3.46).
- The quote is genuine, platform up to date. A verifier approving the code of that quote
  (`0xBbcC8a20c8e8985911048180fB2E07e2A96aC3e8`), announced, then the key enrolled for agent 1
  (transaction `0x270a0c80e749e9132ec9286edc5880e6e1c0722a450eabe47f731dfe4523c93e`, block
  62578716). The agent signed in once and was served, free.
- That approval names one instance, now deleted: it lets no other machine in. The registry's
  verifier is left at that address; the next run announces its own.
- One read of the chain failed once (`listings`) and succeeded at the next pass.

The 0.6.4 system image was not compared with the one dstack publishes.
