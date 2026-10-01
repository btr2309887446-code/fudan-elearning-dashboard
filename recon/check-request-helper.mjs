// Check module 7ca0 (the request helper) and where the F() sanitiser is applied.
import { readFileSync } from 'node:fs';

const js = readFileSync('recon/out/idp-js/js_chunk-71ba4ca7.61b64444.js', 'utf8');

// Module 7ca0 defines the "a" (GET) and "b" (POST) request helpers.
const m = js.indexOf('7ca0:function');
console.log('=== module 7ca0 @' + m + ' ===');
console.log(js.slice(m, m + 1800).replace(/\s{2,}/g, ' '));

console.log('\n\n=== call sites of the F() sanitiser ===');
let i = -1;
let n = 0;
while ((i = js.indexOf('F(', i + 1)) !== -1 && n < 8) {
  const ctx = js.slice(Math.max(0, i - 150), i + 120).replace(/\s{2,}/g, ' ');
  // Only show ones that look like payload sanitising rather than function defs.
  if (/authPara|loginToken|payload|ruleForm|authModuleCode|verifyCode/.test(ctx)) {
    console.log(`--- @${i} ---\n${ctx}`);
    n++;
  }
}
if (n === 0) console.log('(no payload-sanitising call sites found)');
