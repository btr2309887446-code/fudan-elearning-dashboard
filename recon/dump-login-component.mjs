// Dump the full "user-and-pwd" login component from the IdP chunk so the exact
// authExecute payload can be read off the provider's own code.
import { readFileSync } from 'node:fs';

const js = readFileSync('recon/out/idp-js/js_chunk-71ba4ca7.61b64444.js', 'utf8');

function findAll(needle) {
  const out = [];
  let i = -1;
  while ((i = js.indexOf(needle, i + 1)) !== -1) out.push(i);
  return out;
}

console.log('=== all "authPara" occurrences ===');
console.log(findAll('authPara').join(', '));
console.log('\n=== all "getRSApassword" occurrences ===');
console.log(findAll('getRSApassword').join(', '));
console.log('\n=== all "JPK" / encrypt-ish occurrences ===');
for (const kw of ['setPublicKey', 'encrypt(', 'JSEncrypt(', '$jsEncrypt']) {
  console.log(`${kw}: ${findAll(kw).join(', ') || '(none)'}`);
}

// The user-and-pwd component starts at the name:"user-and-pwd" marker.
const compStart = js.indexOf('name:"user-and-pwd"');
console.log(`\n=== component starts @${compStart} ===`);
console.log(js.slice(compStart, compStart + 9000).replace(/\s{2,}/g, ' '));
