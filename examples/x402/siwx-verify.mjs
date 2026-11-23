// Checks a SIGN-IN-WITH-X header with the reference implementation of the x402 extension
// (@x402/extensions) and viem, the way a standard x402 server would for an account that is a
// contract: the message is rebuilt from the header's fields, validated against the server's
// origin, and the signature is checked on chain through ERC-1271.
//
//   node siwx-verify.mjs <rpc url> <chain id> <origin, e.g. http://127.0.0.1:8402> <base64 header> [max age, seconds]
//
// Prints one JSON line: { valid, payer?, reason? }. A sign-in is accepted for five minutes after
// its issue; a longer age can be given to check a recorded one. It does not check the nonce's freshness
// (the server that issued it does), nor what the account holds.
import { createPublicClient, http, defineChain } from 'viem';
import { parseSIWxHeader, validateSIWxMessage, verifySIWxSignature } from '@x402/extensions/sign-in-with-x';

const [rpc, chainId, origin, header, maxAge] = process.argv.slice(2);
const chain = defineChain({ id: Number(chainId), name: 'chain', nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 }, rpcUrls: { default: { http: [rpc] } } });
const client = createPublicClient({ chain, transport: http(rpc) });
try {
  const payload = parseSIWxHeader(header);
  const validation = await validateSIWxMessage(payload, new URL(origin), maxAge ? { maxAge: Number(maxAge) * 1000 } : {});
  if (!validation.isValid) throw new Error(validation.invalidReason);
  const verdict = await verifySIWxSignature(payload, { evmVerifier: client.verifyMessage });
  if (!verdict.isValid) throw new Error(verdict.invalidReason);
  console.log(JSON.stringify({ valid: true, payer: verdict.payer }));
} catch (e) {
  console.log(JSON.stringify({ valid: false, reason: String(e.message).slice(0, 200) }));
}
