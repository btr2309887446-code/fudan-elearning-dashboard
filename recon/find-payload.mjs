// Locate the password-mode authExecute payload builder in the IdP bundle.
import { readFileSync } from 'node:fs';

const js = readFileSync('recon/out/idp-js/js_chunk-71ba4ca7.61b64444.js', 'utf8');

function findAll(needle) {
  const out = [];
  let i = -1;
  while ((i = js.indexOf(needle, i + 1)) !== -1) out.push(i);
  return out;
}

// Regions that mention both authPara and a password-ish key are the ones we want.
const candidates = [];
for (const idx of findAll('authPara')) {
  const window = js.slice(Math.max(0, idx - 900), idx + 900);
  if (/password|loginName|verifyCode|encrypted/i.test(window)) candidates.push(idx);
}
console.log('password-related authPara sites:', candidates.join(', '));

for (const idx of candidates.slice(0, 6)) {
  console.log(`\n=================== @${idx} ===================`);
  console.log(js.slice(Math.max(0, idx - 900), idx + 900).replace(/\s{2,}/g, ' '));
}

// Also: how is the "entityId"/"lck"/"requestType" envelope assembled?
console.log('\n\n=================== requestType:"chain_type" sites ===================');
for (const idx of findAll('chain_type')) {
  console.log(`--- @${idx} ---`);
  console.log(js.slice(Math.max(0, idx - 600), idx + 400).replace(/\s{2,}/g, ' '));
}
