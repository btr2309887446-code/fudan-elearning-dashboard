/**
 * 和 `flutter_app/tool/probe_login.dart` 做同一件事：对真实服务器跑登录链前半段，
 * 把轨迹与 cookie 打出来。
 *
 * 两份输出应当逐步一致——这是判断 Dart 移植有没有偏差的依据。
 * 尤其看每一跳的 set-cookie：`_csrf_token` 落在 elearning 域、
 * `REQID` 落在 id 域，两边必须一样。
 *
 *   node cli/probe-login.ts
 *
 * 不需要凭据，不会消耗登录尝试次数。
 */

import { CookieJar } from '../src/core/cookies.ts';
import { HttpClient } from '../src/core/http.ts';
import { beginLogin } from '../src/core/uis.ts';

const jar = new CookieJar();
const http = new HttpClient(jar);

console.log('=== TS 登录链前半段对真实服务器 ===');
console.log('开始时间', new Date().toISOString());
console.log('');

try {
  const t0 = Date.now();
  const ctx = await beginLogin({ jar, http });
  console.log(`✓ beginLogin 成功（${Date.now() - t0} ms）`);
  console.log('');
  console.log('--- 解析出来的上下文 ---');
  console.log('  lck        =', ctx.lck);
  console.log('  entityId   =', ctx.entityId);
  console.log('  chainCode  =', ctx.chainCode);
  console.log('  moduleCode =', ctx.authModuleCode);
  console.log('  requestType=', ctx.requestType);
  console.log('  spaUrl     =', ctx.spaUrl);
  console.log('  公钥长度   =', ctx.publicKey.length, '字符');
  console.log('');

  console.log('--- Cookie jar（域名:名字，不含值）---');
  const all = jar.all();
  if (all.length === 0) {
    console.log('  （空！）');
  } else {
    for (const c of all) {
      console.log(
        `  ${c.domain}  ${c.name}  path=${c.path} secure=${c.secure} hostOnly=${c.hostOnly}`
      );
    }
  }
  console.log('');

  console.log('--- 发给 id.fudan.edu.cn 的 Cookie 头会是什么 ---');
  const forId = jar.cookieHeader('https://id.fudan.edu.cn/idp/authn/queryAuthMethods');
  console.log('  ', forId ? forId.split('; ').map((p) => p.split('=')[0]).join(', ') : '（无）');
  console.log('');

  console.log('--- 发给 elearning.fudan.edu.cn 的 Cookie 头会是什么 ---');
  const forCanvas = jar.cookieHeader('https://elearning.fudan.edu.cn/api/v1/users/self');
  console.log('  ', forCanvas ? forCanvas.split('; ').map((p) => p.split('=')[0]).join(', ') : '（无）');
  console.log('');

  console.log('--- 完整请求轨迹 ---');
  for (const t of http.trace) {
    const cookies = t.setCookie?.length
      ? `  [set-cookie: ${t.setCookie.map((c) => c.split('=')[0]).join(',')}]`
      : '';
    console.log(
      `  ${t.method} ${t.url} → ${t.status}${t.location ? ' → ' + t.location : ''}${cookies}`
    );
  }
} catch (err) {
  console.log(`✗ 失败：${(err as Error).constructor.name}: ${(err as Error).message}`);
  const stack = (err as Error).stack?.split('\n').slice(0, 6).join('\n');
  if (stack) console.log(stack);
  console.log('');
  console.log('--- 失败前的请求轨迹 ---');
  for (const t of http.trace) {
    const cookies = t.setCookie?.length
      ? `  [set-cookie: ${t.setCookie.map((c) => c.split('=')[0]).join(',')}]`
      : '';
    console.log(
      `  ${t.method} ${t.url} → ${t.status}${t.location ? ' → ' + t.location : ''}${cookies}`
    );
  }
  process.exit(1);
}
