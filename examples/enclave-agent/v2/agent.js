// Agent enclave program. Runs inside an Intel TDX confidential VM (dstack). No dependency.
// It creates its session key in memory at start and never writes, prints or returns it.
// It asks the processor for a quote only over the enrollment digest of ITS OWN key. It signs
// two things only: an order to call mint(bytes32), and an x402 payment for one fixed paid page,
// in one token, under a cap. There is no free-form instruction.
const http = require('http');
const crypto = require('crypto');

// ---------- keccak-256
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

// ---------- secp256k1
const P = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2fn;
const N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;
const G = [0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798n, 0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8n];
function mod(a, m) { const r = a % m; return r >= 0n ? r : r + m; }
function inv(a, m) {
  let [r0, r1, t0, t1] = [mod(a, m), m, 1n, 0n];
  while (r1 !== 0n) { const q = r0 / r1; [r0, r1] = [r1, r0 - q * r1]; [t0, t1] = [t1, t0 - q * t1]; }
  return mod(t0, m);
}
function add(a, b) {
  if (a === null) return b;
  if (b === null) return a;
  if (a[0] === b[0] && mod(a[1] + b[1], P) === 0n) return null;
  const l = a[0] === b[0] ? mod(3n * a[0] * a[0] * inv(2n * a[1], P), P) : mod((b[1] - a[1]) * inv(b[0] - a[0], P), P);
  const x = mod(l * l - a[0] - b[0], P);
  return [x, mod(l * (a[0] - x) - a[1], P)];
}
function mul(k, point) {
  let r = null;
  for (let q = point; k > 0n; k >>= 1n, q = add(q, q)) if (k & 1n) r = add(r, q);
  return r;
}
function scalar() {
  for (;;) { const k = BigInt('0x' + crypto.randomBytes(32).toString('hex')); if (k > 0n && k < N) return k; }
}
const word = (v) => Buffer.from(BigInt(v).toString(16).padStart(64, '0'), 'hex');

const KEY = scalar(); // the session key: lives in this process only
const PUB = mul(KEY, G);
const ADDRESS = '0x' + keccak256(Buffer.concat([word(PUB[0]), word(PUB[1])])).subarray(12).toString('hex');

/// 65-byte signature (r, s, v) of a 32-byte digest, low s.
function sign(digest) {
  const z = BigInt('0x' + digest.toString('hex'));
  for (;;) {
    const k = scalar();
    const R = mul(k, G);
    const r = mod(R[0], N);
    let s = mod(inv(k, N) * (z + r * KEY), N);
    if (r === 0n || s === 0n || R[0] >= N) continue;
    let parity = R[1] & 1n;
    if (s > N / 2n) { s = N - s; parity ^= 1n; }
    return Buffer.concat([word(r), word(s), Buffer.from([27 + Number(parity)])]);
  }
}

// ---------- EIP-712
const text = (t) => keccak256(Buffer.from(t, 'utf8'));
const DOMAIN_TYPE = text('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)');
const ENROLL_TYPE = text('Enrollment(uint256 agentId,address sessionKey,bytes32 evidenceHash,address sponsor,uint256 nonce,uint64 deadline)');
const EXECUTE_TYPE = text('Execute(address target,uint256 value,bytes data,uint256 nonce,uint64 deadline)');
const MESSAGE_TYPE = text('AgentMessage(bytes32 hash)');
const TRANSFER_TYPE = text('TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)');
const MINT_SELECTOR = text('mint(bytes32)').subarray(0, 4);

// ---------- what this agent may buy, fixed in the measured code
const SHOP_URL = 'https://x402.org/protected';
const SHOP_NETWORK = 'eip155:84532'; // Base Sepolia
const SHOP_CHAIN = 84532;
const SHOP_ASSET = '0x036cbd53842c5426634e7929541ec2318f3dcf7e'; // USDC on Base Sepolia
const SHOP_CAP = 20000n; // 0.02 USDC per purchase
function typed(name, chainId, verifyingContract, structHash) {
  const domain = keccak256(Buffer.concat([DOMAIN_TYPE, text(name), text('1'), word(chainId), word(verifyingContract)]));
  return keccak256(Buffer.concat([Buffer.from('1901', 'hex'), domain, structHash]));
}

// ---------- requests: every parameter has a fixed shape; nothing else is read
const DIGITS = '0123456789';
const HEX = DIGITS + 'abcdefABCDEF';
const all = (v, alphabet) => [...v].every((ch) => alphabet.includes(ch));
const hex = (bytes) => (v) => v.length === 2 + 2 * bytes && v.startsWith('0x') && all(v.slice(2), HEX);
const SHAPES = { address: hex(20), bytes32: hex(32), uint: (v) => v.length >= 1 && v.length <= 20 && all(v, DIGITS) };
function params(url, spec) {
  const out = {};
  for (const name of Object.keys(spec)) {
    const value = url.searchParams.get(name);
    if (value === null || !SHAPES[spec[name]](value)) throw new Error('bad parameter: ' + name);
    out[name] = value;
  }
  return out;
}
function quote(reportData) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ report_data: reportData.toString('hex') });
    const req = http.request(
      { socketPath: '/var/run/dstack.sock', path: '/GetQuote', method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) } },
      (res) => { let data = ''; res.on('data', (c) => (data += c)); res.on('end', () => (res.statusCode === 200 ? resolve(JSON.parse(data)) : reject(new Error('quote refused: ' + res.statusCode)))); }
    );
    req.on('error', reject);
    req.end(body);
  });
}

async function handle(url) {
  if (url.pathname === '/') return { sessionKey: ADDRESS };
  if (url.pathname === '/manifest') {
    // What dstack measured: the manifest's hash, its fields, and the hash of each long one.
    const info = await new Promise((resolve, reject) => {
      http.get({ socketPath: '/var/run/dstack.sock', path: '/Info' }, (res) => { let d = ''; res.on('data', (c) => (d += c)); res.on('end', () => resolve(JSON.parse(d))); }).on('error', reject);
    });
    const sha = (t) => crypto.createHash('sha256').update(t).digest('hex');
    const raw = JSON.parse(info.tcb_info).app_compose;
    const parsed = JSON.parse(raw);
    const outline = {};
    for (const k of Object.keys(parsed)) outline[k] = typeof parsed[k] === 'string' && parsed[k].length > 200 ? 'sha256:' + sha(parsed[k]) + ' bytes:' + Buffer.byteLength(parsed[k]) : parsed[k];
    return { composeHash: info.compose_hash, manifestSha256: sha(raw), manifestBytes: Buffer.byteLength(raw), outline: outline };
  }
  if (url.pathname === '/enroll') {
    // A quote over the enrollment digest of this program's own key, and of no other key.
    const q = params(url, { registry: 'address', chainId: 'uint', agentId: 'uint', sponsor: 'address', nonce: 'uint', deadline: 'uint', evidenceHash: 'bytes32' });
    const digest = typed('AttestedAgentRegistry', q.chainId, q.registry, keccak256(Buffer.concat([ENROLL_TYPE, word(q.agentId), word(ADDRESS), Buffer.from(q.evidenceHash.slice(2), 'hex'), word(q.sponsor), word(q.nonce), word(q.deadline)])));
    const answer = await quote(Buffer.concat([digest, Buffer.alloc(32)]));
    return { sessionKey: ADDRESS, digest: '0x' + digest.toString('hex'), quote: '0x' + answer.quote.replace(/^0x/, ''), eventLog: JSON.parse(answer.event_log) };
  }
  if (url.pathname === '/mint') {
    // The only order this agent signs: its account calls mint(bytes32) on a collection.
    const q = params(url, { account: 'address', chainId: 'uint', collection: 'address', content: 'bytes32', nonce: 'uint', deadline: 'uint' });
    const data = Buffer.concat([MINT_SELECTOR, Buffer.from(q.content.slice(2), 'hex')]);
    const digest = typed('AgentAccount', q.chainId, q.account, keccak256(Buffer.concat([EXECUTE_TYPE, word(q.collection), word(0), keccak256(data), word(q.nonce), word(q.deadline)])));
    return { target: q.collection, value: '0', data: '0x' + data.toString('hex'), deadline: q.deadline, signature: '0x' + sign(digest).toString('hex') };
  }
  if (url.pathname === '/buy') {
    // An x402 purchase of the fixed page. The price and the payee come from the shop's own
    // answer; the token, the network and the cap come from this code.
    const q = params(url, { account: 'address' });
    const first = await fetch(SHOP_URL);
    if (first.status !== 402) throw new Error('no payment asked: ' + first.status);
    const asked = JSON.parse(Buffer.from(first.headers.get('payment-required') || '', 'base64').toString('utf8'));
    const offer = (asked.accepts || []).find((a) => a.scheme === 'exact' && a.network === SHOP_NETWORK
      && typeof a.asset === 'string' && a.asset.toLowerCase() === SHOP_ASSET
      && typeof a.payTo === 'string' && SHAPES.address(a.payTo)
      && typeof a.amount === 'string' && SHAPES.uint(a.amount) && BigInt(a.amount) <= SHOP_CAP
      && a.extra && typeof a.extra.name === 'string' && typeof a.extra.version === 'string');
    if (!offer) throw new Error('no acceptable offer');
    const auth = { from: q.account, to: offer.payTo, value: offer.amount, validAfter: '0', validBefore: String(Math.floor(Date.now() / 1000) + 300), nonce: '0x' + crypto.randomBytes(32).toString('hex') };
    const token = keccak256(Buffer.concat([DOMAIN_TYPE, text(offer.extra.name), text(offer.extra.version), word(SHOP_CHAIN), word(SHOP_ASSET)]));
    const transfer = keccak256(Buffer.concat([Buffer.from('1901', 'hex'), token, keccak256(Buffer.concat([TRANSFER_TYPE, word(auth.from), word(auth.to), word(auth.value), word(0), word(auth.validBefore), Buffer.from(auth.nonce.slice(2), 'hex')]))]));
    // The payment is signed as a message of the agent's account, never as a bare hash.
    const digest = typed('AgentAccount', SHOP_CHAIN, q.account, keccak256(Buffer.concat([MESSAGE_TYPE, transfer])));
    const payment = { x402Version: 2, payload: { authorization: auth, signature: '0x' + sign(digest).toString('hex') }, extensions: asked.extensions, resource: asked.resource, accepted: offer };
    const second = await fetch(SHOP_URL, { headers: { 'PAYMENT-SIGNATURE': Buffer.from(JSON.stringify(payment), 'utf8').toString('base64') } });
    const receipt = second.headers.get('payment-response');
    return { status: second.status, paid: { to: auth.to, value: auth.value }, receipt: receipt ? JSON.parse(Buffer.from(receipt, 'base64').toString('utf8')) : null, content: (await second.text()).slice(0, 300) };
  }
  throw new Error('unknown path');
}

http.createServer((req, res) => {
  const done = (code, body) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(body)); };
  if (req.method !== 'GET') return done(405, { error: 'GET only' });
  handle(new URL(req.url, 'http://agent')).then((body) => done(200, body), (e) => done(400, { error: String(e.message) }));
}).listen(8080, () => console.log('agent session key', ADDRESS));

