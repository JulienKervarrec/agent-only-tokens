// SPDX-License-Identifier: CC0-1.0
// Compares the USDC code deployed on a chain with the code this repository tests against
// (../../test/usdc, compiled from Circle's sources). Read-only: three RPC reads, no transaction.
//
//   node check-usdc.mjs                              USDC on Base, public RPC
//   RPC_URL=... TOKEN=0x... node check-usdc.mjs      any other chain or token

import { readFileSync } from "node:fs";
import { createPublicClient, http } from "viem";

const RPC_URL = process.env.RPC_URL ?? "https://mainnet.base.org";
const TOKEN = process.env.TOKEN ?? "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
// Where Circle's proxy keeps the address of its code: keccak256("org.zeppelinos.proxy.implementation").
const IMPLEMENTATION_SLOT = "0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3";
const PLACEHOLDER = "00000000000000000000000000000000005167c4"; // library address our build was linked with

const artifact = (name) => JSON.parse(readFileSync(new URL(`../../test/usdc/${name}.json`, import.meta.url)));
const hex = (code) => code.slice(2).toLowerCase();
// The compiler appends a hash of its input files to the code. It changes with file paths,
// not with the logic, so it is left out of the comparison.
const withoutMetadata = (code) => code.slice(0, code.length - 2 * (parseInt(code.slice(-4), 16) + 2));

const client = createPublicClient({ transport: http(RPC_URL) });
const slot = await client.getStorageAt({ address: TOKEN, slot: IMPLEMENTATION_SLOT });
const implementation = BigInt(slot ?? 0) === 0n ? TOKEN : `0x${slot.slice(26)}`;
const deployed = hex((await client.getCode({ address: implementation })) ?? "0x");

// The token: our creation code ends with the code that gets deployed.
const ours = withoutMetadata(hex(artifact("FiatTokenV2_2").bytecode).slice(-deployed.length));
const theirs = withoutMetadata(deployed);
let library;
let tokenMatches = deployed.length > 0 && ours.length === theirs.length;
for (let i = 0; tokenMatches && i < ours.length; i += 2) {
  if (ours.startsWith(PLACEHOLDER, i)) {
    // The only place the two may differ: the address of the signature library.
    library ??= theirs.slice(i, i + 40);
    tokenMatches = theirs.slice(i, i + 40) === library;
    i += 38;
  } else {
    tokenMatches = ours.slice(i, i + 2) === theirs.slice(i, i + 2);
  }
}

// The signature library (it does the ERC-1271 call): a library's code starts with its own address.
let libraryMatches = false;
if (tokenMatches && library) {
  const ownAddress = (code) => code.slice(0, 2) + "0".repeat(40) + code.slice(42);
  const deployedLibrary = hex((await client.getCode({ address: `0x${library}` })) ?? "0x");
  libraryMatches = deployedLibrary.length > 0
    && ownAddress(withoutMetadata(deployedLibrary)) === ownAddress(withoutMetadata(hex(artifact("SignatureChecker").deployedBytecode)));
}

console.log(`chain ${await client.getChainId()}, block ${await client.getBlockNumber()}`);
console.log(`token ${TOKEN}`);
console.log(`code at ${implementation}: ${tokenMatches ? "identical to test/usdc/FiatTokenV2_2.json" : "DIFFERENT"}`);
if (tokenMatches) {
  console.log(`signature library at 0x${library}: ${libraryMatches ? "identical to test/usdc/SignatureChecker.json" : "DIFFERENT"}`);
}
process.exit(tokenMatches && libraryMatches ? 0 : 1);
