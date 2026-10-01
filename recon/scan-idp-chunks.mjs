// Fetch the lazily-loaded IdP chunks that contain the actual login form logic.
import { writeFileSync, mkdirSync, readFileSync } from 'node:fs';

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
mkdirSync('recon/out/idp-js', { recursive: true });

const chunks = [
  'js/chunk-2d0ddc5d.67f754bf.js',
  'js/chunk-71ba4ca7.61b64444.js',
  'js/chunk-93d0f0b4.660cad89.js',
];

for (const f of chunks) {
  const url = `https://id.fudan.edu.cn/ac/${f}`;
  try {
    const res = await fetch(url, { headers: { 'User-Agent': UA, Referer: 'https://id.fudan.edu.cn/ac/' } });
    const body = await res.text();
    writeFileSync(`recon/out/idp-js/${f.replace(/\//g, '_')}`, body);
    console.log(`${res.status} ${url} -> ${body.length} bytes`);
  } catch (e) {
    console.log(`ERR ${url} :: ${e.message}`);
  }
}

// Now scan every downloaded bundle for the request-shaping identifiers.
const keywords = ['authPara', 'authChainCode', 'loginToken', 'requestType', 'chain_type', 'authModuleCode', 'verifyCodeIsNeed', 'encrypt', 'authnEngine'];
console.log('\n================ scanning bundles ================');

for (const f of chunks) {
  const path = `recon/out/idp-js/${f.replace(/\//g, '_')}`;
  let js;
  try {
    js = readFileSync(path, 'utf8');
  } catch {
    continue;
  }
  console.log(`\n########## ${f} (${js.length} bytes) ##########`);
  for (const kw of keywords) {
    const idx = js.indexOf(kw);
    if (idx === -1) continue;
    console.log(`\n--- "${kw}" @${idx} ---`);
    console.log(js.slice(Math.max(0, idx - 500), Math.min(js.length, idx + 700)).replace(/\n/g, ' '));
  }
}
