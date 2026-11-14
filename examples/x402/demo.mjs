// SPDX-License-Identifier: CC0-1.0
// An agent account buys from a paid API through the real x402 stack, on a local chain.
//
//   chain        anvil, started by this script
//   token        Circle's FiatTokenV2_2 bytecode, unmodified (../../test/usdc)
//   facilitator  the x402 reference facilitator (@x402/core + @x402/evm), served over HTTP
//   merchant     express + the x402 payment middleware
//   agent        the standard x402 fetch client, signing through agentSigner.mjs
//
// No private key is stored: every key is generated at start and funded by the local chain.
// Run `forge build` at the repository root first, then `npm install` and `node demo.mjs` here.

import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import express from "express";
import { createTestClient, createWalletClient, http, keccak256, maxUint256, parseAbi, parseEther, publicActions, toHex, zeroAddress } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { foundry } from "viem/chains";
import { x402Client } from "@x402/core/client";
import { x402Facilitator } from "@x402/core/facilitator";
import { HTTPFacilitatorClient } from "@x402/core/server";
import { toFacilitatorEvmSigner } from "@x402/evm";
import { registerExactEvmScheme as registerClientScheme } from "@x402/evm/exact/client";
import { registerExactEvmScheme as registerFacilitatorScheme } from "@x402/evm/exact/facilitator";
import { ExactEvmScheme as MerchantScheme } from "@x402/evm/exact/server";
import { paymentMiddleware, x402ResourceServer } from "@x402/express";
import { wrapFetchWithPayment } from "@x402/fetch";
import { agentSigner } from "./agentSigner.mjs";

const RPC_PORT = Number(process.env.RPC_PORT ?? 18545);
const NETWORK = `eip155:${foundry.id}`;
const PRICE = 250_000n; // 0.25 USDC
const FUNDING = 1_000_000n; // 1 USDC
const SIGNATURE_CHECKER = "0x00000000000000000000000000000000005167C4"; // library address the token was linked with
const BAD_SIGNATURE = "invalid_exact_evm_signature"; // the facilitator's reason when the payer does not approve

const json = (path) => JSON.parse(readFileSync(new URL(path, import.meta.url)));
const newAccount = () => privateKeyToAccount(generatePrivateKey());
const listen = (app) => new Promise((resolve) => { const s = app.listen(0, "127.0.0.1", () => resolve(s)); });
const urlOf = (server) => `http://127.0.0.1:${server.address().port}`;

// ------------------------------------------------------------ chain

const anvil = spawn(process.env.ANVIL ?? "anvil", ["--port", String(RPC_PORT), "--silent"], { stdio: "ignore" });
const servers = [];
const stop = () => { servers.forEach((s) => s.close()); anvil.kill(); };
process.on("exit", stop);

const transport = http(`http://127.0.0.1:${RPC_PORT}`);
const chain = createTestClient({ chain: foundry, mode: "anvil", transport }).extend(publicActions);
for (let i = 0; ; i++) {
  try { await chain.getChainId(); break; } catch (e) {
    if (i === 50) throw new Error("anvil did not start (is Foundry installed?)");
    await new Promise((r) => setTimeout(r, 100));
  }
}

const wallet = async (account, eth) => {
  if (eth) await chain.setBalance({ address: account.address, value: parseEther(eth) });
  return createWalletClient({ account, chain: foundry, transport }).extend(publicActions);
};
const deploy = async (from, abi, bytecode, args = []) => {
  const hash = await from.deployContract({ abi, bytecode, args });
  return (await chain.waitForTransactionReceipt({ hash })).contractAddress;
};
const send = async (from, address, abi, functionName, args = [], value) => {
  const hash = await from.writeContract({ address, abi, functionName, args, value });
  assert.equal((await chain.waitForTransactionReceipt({ hash })).status, "success", functionName);
};

const sponsor = await wallet(newAccount(), "10"); // deploys everything and sponsors the agent
const relayer = await wallet(newAccount(), "10"); // the facilitator's gas account
const merchant = newAccount();
const sessionKey = newAccount(); // the agent's key: never holds ETH
const attesters = [newAccount(), newAccount(), newAccount()].sort((a, b) => (BigInt(a.address) < BigInt(b.address) ? -1 : 1));

// ------------------------------------------------------------ USDC (Circle's code)

const usdcAbi = parseAbi([
  "function initialize(string,string,string,uint8,address,address,address,address)",
  "function initializeV2(string)",
  "function initializeV2_1(address)",
  "function initializeV2_2(address[],string)",
  "function configureMinter(address,uint256) returns (bool)",
  "function mint(address,uint256) returns (bool)",
  "function balanceOf(address) view returns (uint256)",
]);
await chain.setCode({ address: SIGNATURE_CHECKER, bytecode: json("../../test/usdc/SignatureChecker.json").deployedBytecode });
const usdc = await deploy(sponsor, [], json("../../test/usdc/FiatTokenV2_2.json").bytecode);
const me = sponsor.account.address;
await send(sponsor, usdc, usdcAbi, "initialize", ["USD Coin", "USDC", "USD", 6, me, me, me, me]);
await send(sponsor, usdc, usdcAbi, "initializeV2", ["USD Coin"]);
await send(sponsor, usdc, usdcAbi, "initializeV2_1", ["0x000000000000000000000000000000000000dEaD"]);
await send(sponsor, usdc, usdcAbi, "initializeV2_2", [[], "USDC"]);
await send(sponsor, usdc, usdcAbi, "configureMinter", [me, maxUint256]);
const balance = (who) => chain.readContract({ address: usdc, abi: usdcAbi, functionName: "balanceOf", args: [who] });

// ------------------------------------------------------------ registry and agent

const registryArtifact = json("../../out/AttestedAgentRegistry.sol/AttestedAgentRegistry.json");
const bond = parseEther("0.01");
const registry = await deploy(sponsor, registryArtifact.abi, registryArtifact.bytecode.object, [
  attesters.map((a) => a.address), 2n, bond, 30n * 24n * 3600n, zeroAddress,
]);
const enrollment = {
  agentId: 1n,
  sessionKey: sessionKey.address,
  evidenceHash: keccak256(toHex("demo evidence")),
  sponsor: me,
  nonce: 0n,
  deadline: (await chain.getBlock()).timestamp + 3600n,
};
const approvals = await Promise.all(attesters.slice(0, 2).map((a) => a.signTypedData({
  domain: { name: "AttestedAgentRegistry", version: "1", chainId: foundry.id, verifyingContract: registry },
  types: { Enrollment: [
    { name: "agentId", type: "uint256" }, { name: "sessionKey", type: "address" }, { name: "evidenceHash", type: "bytes32" },
    { name: "sponsor", type: "address" }, { name: "nonce", type: "uint256" }, { name: "deadline", type: "uint64" },
  ] },
  primaryType: "Enrollment",
  message: enrollment,
})));
await send(sponsor, registry, registryArtifact.abi, "enroll",
  [enrollment.agentId, enrollment.sessionKey, enrollment.evidenceHash, enrollment.deadline, approvals], bond);
const agent = await chain.readContract({ address: registry, abi: registryArtifact.abi, functionName: "accountOf", args: [1n] });
await send(sponsor, usdc, usdcAbi, "mint", [agent, FUNDING]);

// ------------------------------------------------------------ facilitator (reference code, over HTTP)

const facilitator = registerFacilitatorScheme(new x402Facilitator(), {
  networks: NETWORK,
  signer: toFacilitatorEvmSigner({
    address: relayer.account.address,
    getCode: (a) => relayer.getCode(a),
    readContract: (a) => relayer.readContract({ ...a, args: a.args ?? [] }),
    verifyTypedData: (a) => relayer.verifyTypedData(a),
    writeContract: (a) => relayer.writeContract({ ...a, args: a.args ?? [] }),
    sendTransaction: (a) => relayer.sendTransaction(a),
    waitForTransactionReceipt: (a) => relayer.waitForTransactionReceipt(a),
  }),
});
const verdicts = []; // what the facilitator answered to each verification
const facilitatorApp = express().use(express.json());
facilitatorApp.post("/verify", async (req, res) => {
  const verdict = await facilitator.verify(req.body.paymentPayload, req.body.paymentRequirements);
  verdicts.push(verdict);
  res.json(verdict);
});
facilitatorApp.post("/settle", async (req, res) => res.json(await facilitator.settle(req.body.paymentPayload, req.body.paymentRequirements)));
facilitatorApp.get("/supported", (_req, res) => res.json(facilitator.getSupported()));
servers.push(await listen(facilitatorApp));

// ------------------------------------------------------------ merchant (a paid API)

const shop = express();
shop.use(paymentMiddleware(
  { "GET /report": {
    accepts: [{
      scheme: "exact",
      network: NETWORK,
      payTo: merchant.address,
      price: { amount: PRICE.toString(), asset: usdc, extra: { name: "USD Coin", version: "2" } },
    }],
    description: "A paid report",
    mimeType: "application/json",
  } },
  new x402ResourceServer(new HTTPFacilitatorClient({ url: urlOf(servers[0]) })).register(NETWORK, new MerchantScheme()),
));
shop.get("/report", (_req, res) => res.json({ report: "paid content" }));
servers.push(await listen(shop));
const reportUrl = `${urlOf(servers[1])}/report`;

// ------------------------------------------------------------ agent (standard x402 client)

const buy = async (signer) => {
  const client = registerClientScheme(new x402Client(), { signer });
  // The agent only pays in this token, and never more than 1 USDC per call.
  client.setSpendControls({ allowedAssets: [{ network: NETWORK, asset: usdc, maxAmountPerPayment: "1000000" }] });
  try {
    const response = await wrapFetchWithPayment(fetch, client)(reportUrl);
    return { status: response.status, body: await response.json().catch(() => undefined) };
  } catch (error) {
    return { status: 0, error: error.message };
  }
};
const lastVerdict = () => verdicts.at(-1)?.invalidReason ?? "accepted";
const check = async (label, expectedAgent, expectedMerchant) => {
  assert.equal(await balance(agent), expectedAgent, `${label}: agent balance`);
  assert.equal(await balance(merchant.address), expectedMerchant, `${label}: merchant balance`);
};

console.log(`agent account ${agent} holds 1 USDC and ${await chain.getBalance({ address: agent })} wei of ETH`);

// 1. Without payment, the API answers 402.
assert.equal((await fetch(reportUrl)).status, 402);
console.log("1. no payment              -> HTTP 402");

// 2. The agent pays: one HTTP call, settled on chain by the facilitator.
let result = await buy(agentSigner(sessionKey, agent));
assert.equal(result.status, 200, JSON.stringify(result));
assert.deepEqual(result.body, { report: "paid content" });
await check("paid", FUNDING - PRICE, PRICE);
console.log(`2. agent pays              -> HTTP 200, facilitator: ${lastVerdict()}, merchant received 0.25 USDC`);

// 3. The session key signing the payment directly, the way a wallet would: refused.
result = await buy({ address: agent, signTypedData: (payment) => sessionKey.signTypedData(payment) });
assert.notEqual(result.status, 200);
assert.equal(lastVerdict(), BAD_SIGNATURE);
await check("raw signature", FUNDING - PRICE, PRICE);
console.log(`3. raw signature           -> refused, facilitator: ${lastVerdict()}`);

// 4. Another key signing for the agent account: refused.
result = await buy(agentSigner(newAccount(), agent));
assert.notEqual(result.status, 200);
assert.equal(lastVerdict(), BAD_SIGNATURE);
await check("wrong key", FUNDING - PRICE, PRICE);
console.log(`4. wrong key               -> refused, facilitator: ${lastVerdict()}`);

// 5. The sponsor freezes the agent: it can no longer pay. Unfrozen, it pays again.
await send(sponsor, registry, registryArtifact.abi, "setFrozen", [1n, true]);
result = await buy(agentSigner(sessionKey, agent));
assert.notEqual(result.status, 200);
assert.equal(lastVerdict(), BAD_SIGNATURE);
await check("frozen", FUNDING - PRICE, PRICE);
console.log(`5. frozen agent            -> refused, facilitator: ${lastVerdict()}`);
await send(sponsor, registry, registryArtifact.abi, "setFrozen", [1n, false]);
result = await buy(agentSigner(sessionKey, agent));
assert.equal(result.status, 200, JSON.stringify(result));
await check("unfrozen", FUNDING - 2n * PRICE, 2n * PRICE);
console.log("   unfrozen agent          -> HTTP 200, merchant received 0.25 USDC");

// The agent and its key never held ETH: the facilitator paid the gas.
assert.equal(await chain.getBalance({ address: agent }), 0n);
assert.equal(await chain.getBalance({ address: sessionKey.address }), 0n);
console.log("agent account and session key still hold 0 ETH: the facilitator paid the gas");
console.log("ALL CHECKS PASSED");
process.exit(0);
