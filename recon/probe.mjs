// Reconnaissance probe for Fudan eLearning (Canvas LMS).
// Read-only: only issues GET requests, never submits credentials.
import { writeFileSync, mkdirSync } from 'node:fs';

const BASE = 'https://elearning.fudan.edu.cn';
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

const paths = [
  '/',
  '/login',
  '/login/cas',
  '/login/saml',
  '/api/v1/courses',
  '/api/v1/users/self',
  '/api/v1/accounts',
  '/about',
  '/doc/api',
  '/favicon.ico',
];

mkdirSync('recon/out', { recursive: true });

async function probe(path, opts = {}) {
  const url = BASE + path;
  const t0 = Date.now();
  try {
    const res = await fetch(url, {
      redirect: 'manual',
      headers: { 'User-Agent': UA, Accept: '*/*', 'Accept-Language': 'zh-CN,zh;q=0.9' },
      ...opts,
    });
    const ms = Date.now() - t0;
    const h = {};
    for (const [k, v] of res.headers) h[k] = v;
    let body = '';
    try {
      body = await res.text();
    } catch {}
    return { path, status: res.status, location: h['location'], headers: h, ms, body };
  } catch (e) {
    return { path, error: e.message, cause: e.cause?.message, ms: Date.now() - t0 };
  }
}

const report = [];
for (const p of paths) {
  const r = await probe(p);
  if (r.error) {
    console.log(`${p.padEnd(22)} ERROR ${r.error} (${r.cause ?? ''})`);
  } else {
    console.log(
      `${p.padEnd(22)} ${r.status} ${r.ms}ms loc=${r.location ?? '-'} ct=${r.headers['content-type'] ?? '-'}`
    );
    const safe = p.replace(/[^a-z0-9]/gi, '_') || 'root';
    if (r.body) writeFileSync(`recon/out${safe === 'root' ? '_root' : safe}.html`, r.body);
    report.push({ path: p, status: r.status, location: r.location, headers: r.headers, ms: r.ms });
  }
}
writeFileSync('recon/out/probe-report.json', JSON.stringify(report, null, 2));

// Follow the redirect chain from '/' so we can see where CAS lives.
console.log('\n=== redirect chain from / ===');
let url = BASE + '/';
for (let i = 0; i < 12; i++) {
  const res = await fetch(url, { redirect: 'manual', headers: { 'User-Agent': UA } });
  const loc = res.headers.get('location');
  console.log(`${i}: ${res.status} ${url}`);
  if (!loc) {
    const body = await res.text();
    writeFileSync('recon/out/final.html', body);
    console.log(`   -> final body ${body.length} bytes -> recon/out/final.html`);
    break;
  }
  const abs = new URL(loc, url).toString();
  console.log(`   -> ${abs}`);
  url = abs;
}
