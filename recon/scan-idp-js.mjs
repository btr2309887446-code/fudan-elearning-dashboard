// Print the regions of the (minified) IdP bundle that build the auth request.
import { readFileSync } from 'node:fs';

const js = readFileSync('recon/out/idp-js/js_app.7d76830c.js', 'utf8');
console.log('bundle length', js.length, '\n');

const keywords = [
  'authExecute',
  'authPara',
  'getJsPublicKey',
  'queryAuthMethods',
  'authnEngine',
  'loginToken',
  'authChainCode',
  'encrypt',
  'JSEncrypt',
  'verifyCode',
  'requestType',
];

for (const kw of keywords) {
  let idx = -1;
  let count = 0;
  const hits = [];
  while ((idx = js.indexOf(kw, idx + 1)) !== -1 && count < 6) {
    hits.push(idx);
    count++;
  }
  console.log(`\n########## "${kw}"  (${count}${count === 6 ? '+' : ''} hits) ##########`);
  for (const i of hits.slice(0, 3)) {
    const start = Math.max(0, i - 320);
    const end = Math.min(js.length, i + 320);
    console.log(`--- @${i} ---`);
    console.log(js.slice(start, end).replace(/\n/g, ' '));
  }
}

console.log('\n\n########## config.js ##########');
console.log(readFileSync('recon/out/idp-js/static_config.js', 'utf8'));
