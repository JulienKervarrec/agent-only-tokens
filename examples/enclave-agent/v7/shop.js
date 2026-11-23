// A small holder-only service, with no dependency, for the run of the seventh program on a real
// machine: one page, served only to an account that signs in (x402 extension sign-in-with-x, an
// EIP-4361 message) and holds a token of one collection. Nothing is sold here (an "auth-only"
// route in the extension's words: the 402 answer offers no payment).
// Each challenge is issued once and expires; the message is rebuilt from the header; the
// signature is checked on chain through ERC-1271 (the caller must be a contract account, as
// every agent account is); then the token balance is read, at every request.
// GET /stats shows the counters, the SHA-256 of the last accepted header and the reason of the
// last refusal, nothing else.
const http = require('http');
const crypto = require('crypto');

const RC = ['0x1','0x8082','0x800000000000808a','0x8000000080008000','0x808b','0x80000001','0x8000000080008081','0x8000000000008009','0x8a','0x88','0x80008009','0x8000000a','0x8000808b','0x800000000000008b','0x8000000000008089','0x8000000000008003','0x8000000000008002','0x8000000000000080','0x800a','0x800000008000000a','0x8000000080008081','0x8000000000008080','0x80000001','0x8000000080008008'].map(BigInt);
const ROT = [0,1,62,28,27,36,44,6,55,20,3,10,43,25,39,41,45,15,21,8,18,2,61,56,14];
const M64 = (1n << 64n) - 1n;
function rotl(x, n) { n = BigInt(n); return n === 0n ? x : ((x << n) | (x >> (64n - n))) & M64; }
function permute(s) {
  for (let round = 0; round < 24; round++) {
    const c = [0, 1, 2, 3, 4].map((x) => s[x] ^ s[x + 5] ^ s[x + 10] ^ s[x + 15] ^ s[x + 20]);
    for (let x = 0; x < 5; x++) {
      const d = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1);
      for (let y = 0; y < 25; y += 5) s[x + y] ^= d;
    }
    const b = new Array(25);
    for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(s[x + 5 * y], ROT[x + 5 * y]);
    for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) s[x + 5 * y] = b[x + 5 * y] ^ (~b[((x + 1) % 5) + 5 * y] & M64 & b[((x + 2) % 5) + 5 * y]);
    s[0] ^= RC[round];
  }
}
function keccak256(data) {
  const padded = Buffer.concat([data, Buffer.alloc(136 - (data.length % 136))]);
  padded[data.length] ^= 0x01;
  padded[padded.length - 1] ^= 0x80;
  const s = new Array(25).fill(0n);
  for (let off = 0; off < padded.length; off += 136) {
    for (let i = 0; i < 17; i++) s[i] ^= padded.readBigUInt64LE(off + 8 * i);
    permute(s);
  }
  const out = Buffer.alloc(32);
  for (let i = 0; i < 4; i++) out.writeBigUInt64LE(s[i], 8 * i);
  return out;
}

const { RPC_URL, NFT, CHAIN_ID, ORIGIN, STATEMENT } = process.env;
const origin = new URL(ORIGIN);
const isHex = (v, bytes) => typeof v === 'string' && v.length === 2 + 2 * bytes && v.startsWith('0x') && [...v.slice(2)].every((ch) => '0123456789abcdefABCDEF'.includes(ch));
if (!isHex(NFT, 20) || ![...String(CHAIN_ID)].every((ch) => '0123456789'.includes(ch))) throw new Error('bad settings');
const selector = (signature) => keccak256(Buffer.from(signature, 'utf8')).subarray(0, 4).toString('hex');
const pad = (hex) => hex.padStart(64, '0');
async function call(to, data) {
  const answer = await fetch(RPC_URL, { method: 'POST', signal: AbortSignal.timeout(20000), headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_call', params: [{ to: to, data: '0x' + data }, 'latest'] }) });
  const body = await answer.json();
  return typeof body.result === 'string' ? body.result : '0x';
}

const issued = new Map(); // nonce -> { issuedAt, expirationTime, used }
// Public counters. Of the last accepted sign-in only a hash is shown, not the header itself.
const stats = { free: 0, refused: 0, lastSignInSha256: null, lastRefusal: null };
const REASONS = ['nonce unknown or already used', 'not this service', 'dates', 'statement', 'format', 'signature refused by the account', 'holds no token'];
function asked() {
  for (const [n, c] of issued) if (Date.parse(c.expirationTime) < Date.now()) issued.delete(n);
  // Bounded: past the limit the oldest challenge is dropped, so a flood cannot stop new ones.
  while (issued.size >= 10000) issued.delete(issued.keys().next().value);
  const nonce = crypto.randomBytes(16).toString('hex');
  const issuedAt = new Date().toISOString();
  const expirationTime = new Date(Date.now() + 300000).toISOString();
  issued.set(nonce, { issuedAt, expirationTime, used: false });
  const info = { domain: origin.host, uri: origin.origin + '/page', version: '1', nonce, issuedAt, expirationTime };
  if (STATEMENT) info.statement = STATEMENT;
  return {
    x402Version: 2,
    resource: { url: origin.origin + '/page', description: 'a page for holders', mimeType: 'text/plain' },
    accepts: [],
    extensions: { 'sign-in-with-x': { info, supportedChains: [{ chainId: 'eip155:' + CHAIN_ID, type: 'eip191', signatureScheme: 'eip1271' }], schema: {} } },
  };
}
async function signedIn(header) {
  const p = JSON.parse(Buffer.from(header, 'base64').toString('utf8'));
  const c = issued.get(p.nonce);
  if (!c || c.used) throw new Error('nonce unknown or already used');
  // Spent at once, whatever follows: one challenge gives one attempt, even to two at the same time.
  c.used = true;
  if (p.domain !== origin.host || p.uri !== origin.origin + '/page' || p.version !== '1' || p.chainId !== 'eip155:' + CHAIN_ID) throw new Error('not this service');
  if (p.issuedAt !== c.issuedAt || p.expirationTime !== c.expirationTime || Date.parse(c.expirationTime) < Date.now()) throw new Error('dates');
  if ((p.statement || '') !== (STATEMENT || '')) throw new Error('statement');
  if (!isHex(p.address, 20) || !isHex(p.signature, 65)) throw new Error('format');
  const message = Buffer.from(p.domain + ' wants you to sign in with your Ethereum account:\n' + p.address + '\n\n' + (p.statement ? p.statement + '\n' : '')
    + '\nURI: ' + p.uri + '\nVersion: 1\nChain ID: ' + CHAIN_ID + '\nNonce: ' + p.nonce + '\nIssued At: ' + p.issuedAt + '\nExpiration Time: ' + p.expirationTime, 'utf8');
  const hash = keccak256(Buffer.concat([Buffer.from('\x19Ethereum Signed Message:\n' + message.length, 'utf8'), message])).toString('hex');
  // isValidSignature(bytes32,bytes): ERC-1271, answered by the account's own code.
  const sig = p.signature.slice(2);
  const verdict = await call(p.address, selector('isValidSignature(bytes32,bytes)') + hash + pad('40') + pad((sig.length / 2).toString(16)) + sig.padEnd(192, '0'));
  if (!verdict.startsWith('0x1626ba7e')) throw new Error('signature refused by the account');
  const balance = await call(NFT, selector('balanceOf(address)') + pad(p.address.slice(2).toLowerCase()));
  if (balance.length !== 66 || BigInt(balance) === 0n) throw new Error('holds no token');
  return p.address;
}

http.createServer((req, res) => {
  // A request line that is not a path ("//") makes URL throw: answered like any other bad request.
  let url;
  try { url = new URL(req.url, origin); } catch (e) { res.writeHead(400); return res.end(); }
  const refuse = () => { res.writeHead(402, { 'payment-required': Buffer.from(JSON.stringify(asked()), 'utf8').toString('base64') }); res.end('{}'); };
  if (req.method !== 'GET') { res.writeHead(405); return res.end(); }
  if (url.pathname === '/stats') { res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end(JSON.stringify(stats)); }
  if (url.pathname !== '/page') { res.writeHead(404); return res.end(); }
  const login = req.headers['sign-in-with-x'];
  if (typeof login !== 'string' || login.length > 4000) return refuse();
  signedIn(login).then((who) => {
    stats.free++;
    stats.lastSignInSha256 = crypto.createHash('sha256').update(login, 'utf8').digest('hex');
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('the page, free for the holder ' + who + ', visit ' + stats.free);
  }, (e) => {
    stats.refused++;
    stats.lastRefusal = REASONS.includes(e.message) ? e.message : 'malformed';
    try { refuse(); } catch (x) { res.writeHead(503); res.end(); }
  });
}).listen(8402);
