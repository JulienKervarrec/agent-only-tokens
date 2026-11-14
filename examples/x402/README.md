# x402 demo: an agent account buys from a paid API

One script runs the whole x402 flow on a local chain, with the real pieces:

| Role | What runs |
|---|---|
| Chain | `anvil`, started by the script |
| Token | Circle's `FiatTokenV2_2` code, unmodified (`../../test/usdc`) |
| Facilitator | the x402 reference facilitator (`@x402/core`, `@x402/evm` 2.31.0), served over HTTP |
| Merchant | an Express API behind the x402 payment middleware |
| Agent | the standard x402 fetch client, with `agentSigner.mjs` as its signer |

```
forge build            # at the repository root
cd examples/x402
npm install
node demo.mjs
```

Expected output:

```
1. no payment              -> HTTP 402
2. agent pays              -> HTTP 200, facilitator: accepted, merchant received 0.25 USDC
3. raw signature           -> refused, facilitator: invalid_exact_evm_signature
4. wrong key               -> refused, facilitator: invalid_exact_evm_signature
5. frozen agent            -> refused, facilitator: invalid_exact_evm_signature
   unfrozen agent          -> HTTP 200, merchant received 0.25 USDC
agent account and session key still hold 0 ETH: the facilitator paid the gas
ALL CHECKS PASSED
```

## The adapter

`agentSigner.mjs` is all an agent needs to use a stock x402 client. The client
asks its signer to sign the payment; the adapter answers with the session key's
signature over that payment wrapped as an `AgentMessage` of the agent account,
and names the account as the payer. The contracts are unchanged.

```js
const client = registerExactEvmScheme(new x402Client(), { signer: agentSigner(sessionKey, agentAccount) });
const response = await wrapFetchWithPayment(fetch, client)("https://api.example/report");
```

The adapter signs whatever payment the client decides to make. Limits on what
the agent may spend are set on the client (`setSpendControls`: allowed tokens
and a cap per payment), as the demo does.

## Is this the USDC that runs on Base?

`check-usdc.mjs` reads the code of a deployed USDC and compares it, byte for
byte, with the code used here. Read-only.

```
node check-usdc.mjs                            # USDC on Base, public RPC
RPC_URL=... TOKEN=0x... node check-usdc.mjs    # another chain or token
```

Result on 14 November 2026, Base mainnet, block 57,208,253: the code behind
USDC (`0x2Ce6311ddAE708829bc0784C967b7d77D19FD779`) and its signature library
(`0x2D943E25e1859ED786AFe4AFB2B42e14EFAC691e`) are identical to `test/usdc`,
apart from the compiler's metadata hash and the library's address. That
comparison was run from a browser against `https://mainnet.base.org`; the
script applies the same comparison and was run here against a local chain only
(genuine code, a modified token, a modified library, an empty address).

## Limits

- Local chain. No payment was made on Base or on a testnet.
- The facilitator is the open-source reference code. A hosted facilitator may
  run other code or add its own rules.
- USDC is upgradeable: Circle can change the code the comparison was made against.
- No key is stored in this folder: the demo generates every key at start.
