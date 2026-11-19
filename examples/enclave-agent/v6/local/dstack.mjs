// A stand-in for dstack's guest agent in the local test: answers GetQuote on the Unix socket with
// a quote that has the raw TDX layout (48-byte header, 584-byte report body) and the requested
// report data at its place, and nothing else. It proves nothing about hardware: only the real
// machine's quote, checked by Intel's DCAP verifier, does.
import http from 'node:http';
import fs from 'node:fs';
const path = process.argv[2];
try { fs.unlinkSync(path); } catch {}
http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    if (req.url !== '/GetQuote') { res.writeHead(404); return res.end('{}'); }
    const rd = Buffer.from(JSON.parse(body).report_data, 'hex');
    const q = Buffer.alloc(48 + 584);
    q.writeUInt16LE(4, 0);
    rd.copy(q, 48 + 520);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ quote: q.toString('hex'), event_log: '[]' }));
  });
}).listen(path);
