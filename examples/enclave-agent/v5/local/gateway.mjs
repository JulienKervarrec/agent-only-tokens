// A stand-in for Phala's confidential AI gateway, for the local test of the fifth program only.
// It speaks the same format (ACI 1: attestation report, signed receipts) with throwaway keys
// made here, and a "quote" that the test's DCAP stub (test/experimental/TdxEnrollment.t.sol)
// accepts without any signature: the stub stands for Intel's check, the rest is checked for real.
// A control path (POST /mode, plain HTTP on another port) makes it cheat in one way at a time.
//
//   node gateway.mjs <https port> <control port> <cert.pem> <key.pem> <other-cert.pem> <other-key.pem> <api key>
import https from 'node:https';
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';

const [port, controlPort, certFile, keyFile, otherCertFile, otherKeyFile, apiKey] = process.argv.slice(2);
const sha256hex = (b) => crypto.createHash('sha256').update(b).digest('hex');
const jcs = (v) => (v === null || typeof v !== 'object' ? JSON.stringify(v)
  : Array.isArray(v) ? '[' + v.map(jcs).join(',') + ']'
  : '{' + Object.keys(v).sort().map((k) => JSON.stringify(k) + ':' + jcs(v[k])).join(',') + '}');
const spki = (pem) => sha256hex(new crypto.X509Certificate(fs.readFileSync(pem)).publicKey.export({ type: 'spki', format: 'der' }));

const signer = crypto.generateKeyPairSync('ed25519');
const signerHex = signer.publicKey.export({ type: 'spki', format: 'der' }).subarray(12).toString('hex');
const appCompose = JSON.stringify({ name: 'stand-in gateway', note: 'local test' });
const receipts = new Map();
let mode = 'honest'; // honest | skip | bad-signature | bad-answer-hash | unverified-upstream | wrong-tls | stale-nonce | no-receipt

function keyset() {
  return {
    subject: null,
    not_after: Math.floor(Date.now() / 1000) + 601, // so the agent asks for a fresh report each time
    receipt_signing_keys: [{ key_id: 'local-receipt-ed25519', algo: 'ed25519', public_key: signerHex }],
    e2ee_public_keys: [],
    tls_public_keys: [{ spki_sha256: spki(certFile), domain: 'localhost' }],
  };
}
function report(nonce) {
  const ks = keyset();
  const digest = 'sha256:' + sha256hex(jcs(ks));
  const usedNonce = mode === 'stale-nonce' ? '00'.repeat(32) : nonce;
  const reportData = sha256hex(`{"keyset_digest":"${digest}","nonce":"${usedNonce}","purpose":"aci.report_data.v1"}`);
  // RTMR3 events: the compose hash, then system-ready. Digests are 48 bytes, as in dstack.
  const events = [
    { imr: 3, event: 'compose-hash', event_payload: sha256hex(appCompose), digest: crypto.createHash('sha384').update(sha256hex(appCompose)).digest('hex') },
    { imr: 3, event: 'system-ready', event_payload: '', digest: crypto.createHash('sha384').update('system-ready').digest('hex') },
  ];
  let mr = Buffer.alloc(48);
  for (const e of events) mr = crypto.createHash('sha384').update(Buffer.concat([mr, Buffer.from(e.digest, 'hex')])).digest();
  // A TDX quote shape: 48-byte header, then the 584-byte report body (RTMR3 at 472, report data at 520).
  const quote = Buffer.alloc(48 + 584);
  mr.copy(quote, 48 + 472);
  Buffer.from(reportData, 'hex').copy(quote, 48 + 520);
  return {
    api_version: 'aci/1',
    workload_keyset_digest: digest,
    attestation: {
      tee_type: 'tdx', workload_keyset: ks, report_data: reportData,
      source_provenance: { repo_url: 'local', repo_commit: 'local' },
      evidence: { quote: quote.toString('hex'), event_log: JSON.stringify(events), app_compose: appCompose },
    },
  };
}
function receipt(id, requestBody, responseBody, ks) {
  const r = {
    api_version: 'aci/1', receipt_id: id, key_id: 'local-receipt-ed25519', endpoint: '/v1/chat/completions', method: 'POST',
    served_at: Math.floor(Date.now() / 1000), workload_keyset_digest: 'sha256:' + sha256hex(jcs(ks)),
    event_log: [
      { type: 'request.received', body_hash: 'sha256:' + sha256hex(requestBody) },
      { type: 'upstream.verified', result: mode === 'unverified-upstream' ? 'unverified' : 'verified', required: true, session_id: 'ab'.repeat(32) },
      { type: 'response.returned', body_hash: 'sha256:' + sha256hex(mode === 'bad-answer-hash' ? Buffer.from('other') : responseBody) },
    ],
  };
  let sig = crypto.sign(null, Buffer.from(jcs(r)), signer.privateKey).toString('hex');
  if (mode === 'bad-signature') sig = (sig[0] === 'a' ? 'b' : 'a') + sig.slice(1);
  return { ...r, signature: sig };
}

let lastKeyset = keyset();
const handler = (req, res) => {
  const url = new URL(req.url, 'https://localhost');
  const send = (code, body, headers = {}) => { res.writeHead(code, { 'Content-Type': 'application/json', ...headers }); res.end(body); };
  if (url.pathname === '/v1/aci/attestation') {
    const rep = report(url.searchParams.get('nonce') || '');
    lastKeyset = rep.attestation.workload_keyset;
    return send(200, JSON.stringify(rep));
  }
  if (req.headers.authorization !== 'Bearer ' + apiKey) return send(401, '{"error":"bad key"}');
  if (url.pathname === '/v1/chat/completions' && req.method === 'POST') {
    const parts = [];
    req.on('data', (c) => parts.push(c));
    req.on('end', () => {
      const requestBody = Buffer.concat(parts);
      const answer = mode === 'skip' ? 'SKIP' : 'BUY';
      const responseBody = Buffer.from(JSON.stringify({ id: 'local', choices: [{ index: 0, message: { role: 'assistant', content: answer }, finish_reason: 'stop' }] }));
      const id = 'rcpt-' + crypto.randomBytes(12).toString('hex');
      receipts.set(id, receipt(id, requestBody, responseBody, lastKeyset));
      send(200, responseBody, mode === 'no-receipt' ? {} : { 'x-receipt-id': id });
    });
    return;
  }
  const m = url.pathname.match(/^\/v1\/aci\/receipts\/(rcpt-[0-9a-f]+)$/);
  if (m && receipts.has(m[1])) return send(200, JSON.stringify(receipts.get(m[1])));
  send(404, '{"error":"not found"}');
};

// The TLS key served: the attested one, or, in wrong-tls mode, another valid certificate for localhost.
const good = { cert: fs.readFileSync(certFile), key: fs.readFileSync(keyFile) };
const other = { cert: fs.readFileSync(otherCertFile), key: fs.readFileSync(otherKeyFile) };
const server = https.createServer(good, handler);
server.listen(Number(port), '127.0.0.1');

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://control');
  if (req.method === 'POST' && url.pathname === '/mode') {
    mode = url.searchParams.get('to') || 'honest';
    server.setSecureContext(mode === 'wrong-tls' ? other : good);
    res.end(mode);
    return;
  }
  res.writeHead(404); res.end();
}).listen(Number(controlPort), '127.0.0.1');
console.log('stand-in gateway on', port);
