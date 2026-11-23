# Sixth program on real machines, 19 November 2026

Two Phala Cloud machines (dstack 0.5.15, `tdx.small`, our pre-launch script), one after the
other, both deleted. About 75 minutes in all, about 0.05 $ of credit with the model's answers.

On Base Sepolia (all in `deployments/base-sepolia.json`): a fresh registry (2 of 3 attesters,
notice 120 s), a sale venue approved with notice, a collection, and a selling agent (agent 2, a
test key, not in a machine) that listed three tokens: token 1 at 0.02 USDC (within the agent's
cap of 0.03), token 2 at 0.50 USDC (above it), token 3 at 0.01 USDC without approving the venue.

## First machine: the first version of the program

Compose hash `38e23083…3dc8` (`docker-compose-first.yml`), shown by Phala Cloud before deployment
and equal to the one computed beforehand. Its enrollment quote (`quote-enroll.hex`): genuine,
platform up to date; a verifier approving exactly that code, announced, then the key enrolled
with no attester signature, and an allowance of 0.05 USDC a day opened (allowance 3). The agent
signed one draw (0.03 USDC), relayed.

The model was asked five times, five minutes apart, whether to buy the paid page; it answered
`SKIP` each time, every answer verified. This version asked about a token only after buying a
page, so it never did: nothing was bought. `journal.json` is its journal (six entries: the draw,
five decisions), answered to our nonce `0xb300c065…c538`.

## Second machine: the token question no longer waits for a page

Compose hash `cd3fbbd8cf98f462ce6d8132e6b68bd8bb40babc339a3dc2d2c14cbd8933408e`
(`docker-compose-second.yml`; the program in `v6/` has changed since), shown by Phala Cloud and
equal to the one computed. Its quote (`quote-enroll-second.hex`):
genuine, up to date. A second verifier, announced, then the new key enrolled for the same agent
and account, with no attester signature; nothing else was changed.

Within a minute the agent found token 1 on the venue (and not tokens 2 and 3), asked the model,
got a verified `BUY`, and signed one order of its account: approve exactly 0.02 USDC to the venue
and buy token 1 at exactly 0.02 USDC. We relayed it (we pay the gas and can change nothing):
transaction `0x37d5d10fcf1e20e19796574f8a86c5867c05c2d16a05935ca2da8c05ca53f301`, block 60897302.
Token 1 now belongs to the agent's account, the seller received 0.02 USDC, no approval is left on
the venue, tokens 2 and 3 stayed with the seller. Then a page question: `SKIP`. Requests from
outside (`/buy?id=2`, `/order`, `/sign`, `/mint`, `/list`, `/journal/append`, `POST /`) were refused.

`journal-second.json` is its journal, answered to our nonce `0x08bb0fe8…1670`: the token
decision (`BUY`, verified), the token order, the page decision (`SKIP`). The order's data hash in
the journal (`11df61bd…faa0`) is the sha256 of the calldata we relayed.

## Checking the journals

    python3 tools/verify_journal.py examples/enclave-agent/run-2026-11-19-v6/journal-second.json \
      --nonce 0x08bb0fe806136c8314d430826bc20a1950223e85c1126d4b75af396ceb731670 \
      --rpc https://sepolia.base.org --dcap 0xaDdeC7e85c2182202b66E331f2a4A0bBB2cEEa1F \
      --compose-hash cd3fbbd8cf98f462ce6d8132e6b68bd8bb40babc339a3dc2d2c14cbd8933408e

    python3 tools/verify_journal.py examples/enclave-agent/run-2026-11-19-v6/journal.json \
      --nonce 0xb300c065a062aedfc504cd684db41ce5cb1775918c72dfd4728f2ed8f623c538 \
      --rpc https://sepolia.base.org --dcap 0xaDdeC7e85c2182202b66E331f2a4A0bBB2cEEa1F \
      --compose-hash 38e23083edc8974f3be2f49e4b4c02239c6611d7f59efa1478eff5b9b62e3dc8

Results on 19 November 2026: 3 and 6 entries, heads `0x9aed0b24…74a1` and `0xbecdeddf…5abe`,
each bound to its nonce; quotes genuine (security level 0), production machines, programs as
given (read from MRCONFIGID). With another program's hash, the check fails. The answers leave out
the event log, which is the same as in the enrollment quotes.

Since 23 November 2026 the same command takes `--verifier`, the registry's enrollment verifier
of that machine (`0xfd484A1E7bd15c201E14b2462CE8C82ADa0039EB` for the second,
`0xba9e664FE43965cA7eA0a5c427A9FC9B334290e7` for the first): it then also checks that the whole
measured code of the quote, system image included, is the one that verifier approves. Both pass,
and each fails with the other's verifier. The two machines ran dstack OS 0.5.15 exactly as
published (`tools/dstack_image.py`, study section 3.20).
