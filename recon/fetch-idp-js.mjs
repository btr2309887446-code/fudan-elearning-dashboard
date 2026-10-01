// Download the IdP's own SPA bundle and inspect how IT builds the authExecute
// request. This is the ground truth; matching it exactly avoids burning the
// user's limited login attempts.
import { writeFileSync, mkdirSync } from 'node:fs';

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
mkdirSync('recon/out/idp-js', { recursive: true });

const files = ['js/app.7d76830c.js', 'js/chunk-vendors.9b90a609.js', 'static/config.js'];
for (const f of files) {
  const url = `https://id.fudan.edu.cn/ac/${f}`;
  try {
    const res = await fetch(url, { headers: { 'User-Agent': UA, Referer: 'https://id.fudan.edu.cn/ac/' } });
    const body = await res.text();
    const name = f.replace(/\//g, '_');
    writeFileSync(`recon/out/idp-js/${name}`, body);
    console.log(`${res.status} ${url} -> ${body.length} bytes`);
  } catch (e) {
    console.log(`ERR ${url} :: ${e.message}`);
  }
}
