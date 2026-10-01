// Validate the Fudan UIS (id.fudan.edu.cn) auth endpoints WITHOUT submitting credentials.
// Steps 1-3 of the login chain only.
import { writeFileSync, mkdirSync } from 'node:fs';
mkdirSync('recon/out', { recursive: true });

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

// --- tiny cookie jar -------------------------------------------------------
const jar = new Map();
function store(res, url) {
  const list = res.headers.getSetCookie?.() ?? [];
  for (const c of list) {
    const [pair] = c.split(';');
    const idx = pair.indexOf('=');
    if (idx < 0) continue;
    jar.set(pair.slice(0, idx).trim(), pair.slice(idx + 1).trim());
  }
}
function cookieHeader() {
  return [...jar.entries()].map(([k, v]) => `${k}=${v}`).join('; ');
}
async function req(url, opts = {}) {
  const headers = { 'User-Agent': UA, 'Accept-Language': 'zh-CN,zh;q=0.9', ...(opts.headers ?? {}) };
  if (jar.size) headers['Cookie'] = cookieHeader();
  const res = await fetch(url, { ...opts, headers, redirect: opts.redirect ?? 'manual' });
  store(res, url);
  return res;
}
function show(name, res, body) {
  console.log(`\n--- ${name} ---`);
  console.log(`status=${res.status} ct=${res.headers.get('content-type')}`);
  console.log(`location=${res.headers.get('location') ?? '-'}`);
  console.log(`setCookie=${(res.headers.getSetCookie?.() ?? []).map((c) => c.split(';')[0]).join(' | ') || '-'}`);
  if (body !== undefined) console.log(`body(${body.length}): ${body.slice(0, 700)}`);
}

// --- step 0: which services does the IdP serve? ---------------------------
const HAS_JOSE = typeof globalThis.crypto?.subtle !== 'undefined';
console.log('node', process.version, 'webcrypto:', HAS_JOSE);

// --- step 1: hit canvas CAS entry, land on the IdP SPA --------------------
let url = 'https://elearning.fudan.edu.cn/login/cas';
for (let i = 0; i < 6; i++) {
  const res = await req(url);
  const loc = res.headers.get('location');
  console.log(`hop${i}: ${res.status} ${url}${loc ? ' -> ' + new URL(loc, url).toString() : ''}`);
  if (!loc) break;
  url = new URL(loc, url).toString();
}

const u = new URL(url);
const frag = u.hash.replace(/^#\/?/, '');
const fragQuery = new URLSearchParams(frag.includes('?') ? frag.slice(frag.indexOf('?') + 1) : '');
const lck = fragQuery.get('lck');
const entityId = fragQuery.get('entityId');
console.log(`\nIDP_SPA_HOST=${u.host}`);
console.log(`lck=${lck}`);
console.log(`entityId=${entityId}`);
console.log(`theme=${fragQuery.get('theme')}`);

const ID = 'https://id.fudan.edu.cn';

// --- step 2: public key ---------------------------------------------------
const pkRes = await req(`${ID}/idp/authn/getJsPublicKey`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json;charset=UTF-8', Origin: ID, Referer: url },
  body: '{}',
});
let pkBody = await pkRes.text();
show('POST /idp/authn/getJsPublicKey', pkRes, pkBody);
try {
  const j = JSON.parse(pkBody);
  writeFileSync('recon/out/pubkey.json', JSON.stringify(j, null, 2));
  console.log('publicKey first80=', String(j.data).slice(0, 80));
} catch {}

// --- step 3: query auth methods ------------------------------------------
const qRes = await req(`${ID}/idp/authn/queryAuthMethods`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json;charset=UTF-8', Origin: ID, Referer: url },
  body: JSON.stringify({ lck, entityId }),
});
const qBody = await qRes.text();
show('POST /idp/authn/queryAuthMethods', qRes, qBody);
try {
  const j = JSON.parse(qBody);
  writeFileSync('recon/out/queryAuthMethods.json', JSON.stringify(j, null, 2));
  console.log('second=', j.second);
  console.log('moduleCodes=', (j.data ?? []).map((m) => m.moduleCode).join(','));
} catch {}

// --- step 4: does the IdP SPA shell / its JS reveal anything? -------------
const shell = await req(url);
const shellBody = await shell.text();
writeFileSync('recon/out/idp-spa.html', shellBody);
console.log(`\nSPA shell ${shellBody.length} bytes -> recon/out/idp-spa.html`);
const scripts = [...shellBody.matchAll(/<script[^>]+src=["']([^"']+)["']/g)].map((m) => m[1]);
console.log('scripts=', scripts.join('\n         '));
