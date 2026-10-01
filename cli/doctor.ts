/**
 * Dry-run doctor: exercises the whole UIS login chain EXCEPT the step that
 * submits credentials, so it is safe to run and proves the protocol still
 * matches what this app expects.
 *
 *   node cli/doctor.ts
 */

import { createPublicKey } from 'node:crypto';
import { CookieJar } from '../src/core/cookies.ts';
import { HttpClient } from '../src/core/http.ts';
import { CANVAS_BASE, ID_BASE, ID_HOST, encryptPassword, extractTicketTarget, toSpkiPem } from '../src/core/uis.ts';

const results: { name: string; ok: boolean; info: string }[] = [];
function check(name: string, ok: boolean, info = ''): boolean {
  results.push({ name, ok, info });
  console.log(`${ok ? '  OK  ' : ' FAIL '} ${name}${info ? '  — ' + info : ''}`);
  return ok;
}

console.log('=== 复旦大学 eLearning 连接自检 ===\n');

const jar = new CookieJar();
const http = new HttpClient(jar);

// 1. Canvas reachable -------------------------------------------------------
console.log('[1] eLearning 可达性');
try {
  const res = await http.raw(CANVAS_BASE + '/', { timeoutMs: 15000 });
  const isCanvas = /canvas/i.test(res.body);
  check('eLearning 首页可访问', res.status === 200, `HTTP ${res.status}`);
  check('确认是 Canvas 实例', isCanvas, isCanvas ? '页面含 Canvas 标识' : '未找到 Canvas 标识');
} catch (err) {
  check('eLearning 首页可访问', false, (err as Error).message);
  console.log('\n无法连接 eLearning，请确认已连接校园网或 VPN。');
  process.exit(1);
}

// 2. CAS redirect chain -----------------------------------------------------
console.log('\n[2] CAS 跳转链');
let spaUrl = '';
try {
  const res = await http.request(CANVAS_BASE + '/login/cas', { timeoutMs: 15000 });
  spaUrl = res.url;
  for (const t of http.trace) {
    console.log(`      ${t.status} ${t.url}${t.location ? '\n         -> ' + t.location : ''}`);
  }
  check('跳转到统一身份认证', res.url.includes(ID_HOST), res.url.slice(0, 110));
} catch (err) {
  check('跳转到统一身份认证', false, (err as Error).message);
  process.exit(1);
}

// 3. parse lck / entityId ---------------------------------------------------
console.log('\n[3] 解析 IdP 参数');
const hash = new URL(spaUrl).hash.replace(/^#/, '');
let lck: string | null = null;
let entityId: string | null = null;
try {
  const parsed = new URL(ID_BASE + (hash.startsWith('/') ? hash : '/' + hash));
  lck = parsed.searchParams.get('lck');
  entityId = parsed.searchParams.get('entityId');
} catch {}
check('解析出 lck', !!lck, lck ?? '(空)');
check('解析出 entityId', !!entityId, entityId ?? '(空)');
if (!lck || !entityId) process.exit(1);

// 4. public key -------------------------------------------------------------
console.log('\n[4] 获取 RSA 公钥');
let publicKey: string | null = null;
try {
  const res = await http.postJson(`${ID_BASE}/idp/authn/getJsPublicKey`, {}, {
    timeoutMs: 15000,
    headers: { Origin: ID_BASE, Referer: spaUrl },
  });
  publicKey = (JSON.parse(res.body) as { data?: string }).data ?? null;
  check('公钥接口返回 data', !!publicKey, publicKey ? `${publicKey.length} 字符` : '空');
} catch (err) {
  check('公钥接口返回 data', false, (err as Error).message);
}

// 5. RSA encryption actually works -----------------------------------------
console.log('\n[5] RSA 加密（用真实公钥加密一段测试串）');
if (publicKey) {
  try {
    // Derive the expected ciphertext size from the key itself rather than
    // hard-coding it: this instance hands out a 3072-bit key, not 2048.
    const key = createPublicKey(toSpkiPem(publicKey));
    const bits = (key.asymmetricKeyDetails?.modulusLength as number | undefined) ?? 0;
    const expected = Math.ceil(bits / 8);
    const cipher = encryptPassword('__probe__', publicKey);
    const der = Buffer.from(cipher, 'base64');
    check(
      '公钥可解析且加密成功',
      bits > 0 && der.length === expected,
      `${bits} 位密钥，密文 ${der.length} 字节（期望 ${expected}）`
    );
  } catch (err) {
    check('公钥可解析且加密成功', false, (err as Error).message);
  }
}

// 6. auth methods -----------------------------------------------------------
console.log('\n[6] 查询可用认证方式');
try {
  const res = await http.postJson(
    `${ID_BASE}/idp/authn/queryAuthMethods`,
    { lck, entityId },
    { timeoutMs: 15000, headers: { Origin: ID_BASE, Referer: spaUrl } }
  );
  const parsed = JSON.parse(res.body) as {
    second?: boolean;
    data?: { moduleCode?: string; moduleName?: string; authChainCode?: string }[];
  };
  const codes = (parsed.data ?? []).map((m) => m.moduleCode).join(', ');
  check('返回认证方式列表', (parsed.data ?? []).length > 0, codes);
  const pwd = (parsed.data ?? []).find((m) => m.moduleCode === 'userAndPwd');
  check('包含「用户名密码」方式', !!pwd?.authChainCode, pwd?.authChainCode ?? '(未找到)');
  check('未强制二次验证', parsed.second !== true, parsed.second === true ? 'second=true' : 'second=false');
} catch (err) {
  check('返回认证方式列表', false, (err as Error).message);
}

// 7. offline parser unit checks --------------------------------------------
console.log('\n[7] 离线解析器单元检查');
{
  const html = `<form id="logon" method="post" action="https://elearning.fudan.edu.cn/login/cas?service=abc&amp;x=1"><input type="hidden" id="ticket" value="ST-123-xyz"></form>`;
  const t = extractTicketTarget(html);
  check('解析 #logon[action] 与 #ticket[value]', t?.action === 'https://elearning.fudan.edu.cn/login/cas?service=abc&x=1' && t.ticket === 'ST-123-xyz', JSON.stringify(t));

  const html2 = `<input value="T-9" id="ticket"/><form action='/a?b=1' id='logon'></form>`;
  const t2 = extractTicketTarget(html2);
  check('兼容属性顺序 / 单引号 / 自闭合', t2?.action === '/a?b=1' && t2.ticket === 'T-9', JSON.stringify(t2));

  check('找不到元素时返回 null', extractTicketTarget('<html>nope</html>') === null);
}

// 8. cookie jar checks ------------------------------------------------------
console.log('\n[8] Cookie 容器单元检查');
{
  const j = new CookieJar();
  j.setFromResponse('https://id.fudan.edu.cn/idp/x', ['REQID=abc; Path=/; Secure; HttpOnly']);
  check('域内匹配发送', j.getCookieHeader('https://id.fudan.edu.cn/other')?.includes('REQID=abc') === true);
  check('跨域不发送', j.getCookieHeader('https://elearning.fudan.edu.cn/') === undefined);
  j.setFromResponse('https://elearning.fudan.edu.cn/login', [
    '_normandy_session=xyz; path=/; secure; HttpOnly',
  ]);
  check('多域互不干扰', j.getCookieHeader('https://elearning.fudan.edu.cn/courses')?.includes('_normandy_session=xyz') === true
    && j.getCookieHeader('https://elearning.fudan.edu.cn/courses')?.includes('REQID') === false);
  j.setFromResponse('https://id.fudan.edu.cn/', ['REQID=gone; Path=/; Max-Age=0']);
  check('Max-Age=0 删除 Cookie', j.getCookieHeader('https://id.fudan.edu.cn/') === undefined);
}

// summary -------------------------------------------------------------------
const failed = results.filter((r) => !r.ok);
console.log(`\n=== 结果：${results.length - failed.length}/${results.length} 项通过 ===`);
if (failed.length) {
  console.log('未通过：');
  for (const f of failed) console.log(`  - ${f.name} ${f.info}`);
  process.exit(1);
}
console.log('链路自检全部通过，可以安全地进行真实登录。');
