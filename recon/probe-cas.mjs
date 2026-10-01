// Probe the Fudan UIS / CAS login page shape (no credentials submitted).
import { writeFileSync, mkdirSync } from 'node:fs';
mkdirSync('recon/out', { recursive: true });

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

async function chain(start, max = 15) {
  let url = start;
  const hops = [];
  for (let i = 0; i < max; i++) {
    const res = await fetch(url, { redirect: 'manual', headers: { 'User-Agent': UA } });
    const loc = res.headers.get('location');
    const setCookie = res.headers.getSetCookie?.() ?? [];
    hops.push({ url, status: res.status, loc, setCookie });
    console.log(`${i}: ${res.status} ${url}`);
    if (setCookie.length) setCookie.forEach((c) => console.log(`     set-cookie: ${c.split(';')[0]}`));
    if (!loc) {
      const body = await res.text();
      writeFileSync('recon/out/cas-login-page.html', body);
      console.log(`   FINAL body ${body.length} bytes -> recon/out/cas-login-page.html`);
      return hops;
    }
    console.log(`   -> ${new URL(loc, url).toString()}`);
    url = new URL(loc, url).toString();
  }
  return hops;
}

console.log('=== CAS chain from /login/cas ===');
const hops = await chain('https://elearning.fudan.edu.cn/login/cas');
writeFileSync('recon/out/cas-chain.json', JSON.stringify(hops, null, 2));
