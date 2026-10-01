/**
 * 探测 Canvas 的文件 / 文件夹接口在本实例上是否可用（学生视角）。
 * 只看 401（路由存在，需登录）还是 404（路由不存在），不提交任何凭据。
 *
 *   node recon/probe-files.mjs
 */

const BASE = 'https://elearning.fudan.edu.cn';
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

const routes = [
  '/api/v1/courses/1/files',
  '/api/v1/courses/1/files?per_page=100',
  '/api/v1/courses/1/folders',
  '/api/v1/courses/1/folders?per_page=100',
  '/api/v1/folders/1',
  '/api/v1/folders/1/files',
  '/api/v1/folders/1/folders',
  '/api/v1/users/self/files',
  '/api/v1/users/self/folders',
  '/api/v1/files/1',
  '/api/v1/courses/1/files/1',
  '/api/v1/courses/1/files/quotas',
  '/api/v1/courses/1/usage_rights',
  '/api/v1/courses/1/modules?include[]=items',
  '/api/v1/courses/1/front_page',
  '/files/1/download',
  '/courses/1/files',
];

const rows = [];
for (const r of routes) {
  try {
    const res = await fetch(BASE + r, {
      redirect: 'manual',
      headers: { 'User-Agent': UA, 'Accept-Language': 'zh-CN,zh;q=0.9' },
    });
    let snippet = '';
    if (res.status !== 404) {
      snippet = (await res.text()).replace(/\s+/g, ' ').slice(0, 90);
    }
    rows.push({ route: r, status: res.status });
    console.log(`${String(res.status).padEnd(4)} ${r}${snippet ? '  :: ' + snippet : ''}`);
  } catch (e) {
    console.log(`ERR  ${r} :: ${e.message}`);
  }
}

console.log('\n=== 汇总 ===');
const exists = rows.filter((r) => r.status === 401).map((r) => r.route);
const missing = rows.filter((r) => r.status === 404).map((r) => r.route);
console.log(`存在需登录 (401)：${exists.length} 个`);
for (const r of exists) console.log(`   ✓ ${r}`);
console.log(`不存在 (404)：${missing.length} 个`);
for (const r of missing) console.log(`   ✗ ${r}`);
