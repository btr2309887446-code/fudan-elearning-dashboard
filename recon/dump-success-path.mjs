// Read the success path: what the IdP does with loginToken, and how it submits
// to authnEngine (form post + locale param).
import { readFileSync } from 'node:fs';

const js = readFileSync('recon/out/idp-js/js_chunk-71ba4ca7.61b64444.js', 'utf8');

const i = js.indexOf('getSubmitUrl:function');
console.log('=== getSubmitUrl @' + i + ' ===');
console.log(js.slice(i, i + 2600).replace(/\s{2,}/g, ' '));

// The form-based submitter.
const j = js.indexOf('function I(e,t)');
console.log('\n\n=== form submitter function I @' + j + ' ===');
console.log(js.slice(j, j + 1400).replace(/\s{2,}/g, ' '));

// Where sessionStorage lck/entityId get seeded.
console.log('\n\n=== sessionStorage lck / entityId seeding ===');
for (const kw of ['setItem("lck"', "setItem('lck'", 'setItem("entityId"', "setItem('entityId'"]) {
  let k = -1;
  let n = 0;
  while ((k = js.indexOf(kw, k + 1)) !== -1 && n < 2) {
    console.log(`--- "${kw}" @${k} ---`);
    console.log(js.slice(Math.max(0, k - 400), k + 300).replace(/\s{2,}/g, ' '));
    n++;
  }
}
