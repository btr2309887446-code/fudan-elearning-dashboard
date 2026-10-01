/**
 * 下载机制的实测。
 *
 * 起一个本地 HTTP 服务器来验证真实行为，而不是只检查代码：
 * 流式写入、进度回调、同名同大小跳过、.part 中间文件、
 * 路径逃逸防护、404 失败记录、瞬时故障重试、Cookie 是否带上。
 *
 *   node cli/test-download.ts
 */

import { createServer, type Server } from 'node:http';
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { CookieJar } from '../src/core/cookies.ts';
import { DownloadManager, safeJoin, type DownloadProgress } from '../src/main/download.ts';

let passed = 0;
let failed = 0;

function check(name: string, ok: boolean, info = ''): void {
  if (ok) {
    passed += 1;
    console.log(`  OK   ${name}${info ? '  — ' + info : ''}`);
  } else {
    failed += 1;
    console.log(` FAIL  ${name}${info ? '  — ' + info : ''}`);
  }
}

const tmp = mkdtempSync(join(tmpdir(), 'elearning-dl-'));
const root = join(tmp, 'downloads');
mkdirSync(root, { recursive: true });

// ---------------------------------------------------------------------------
// 本地测试服务器
// ---------------------------------------------------------------------------

const PAYLOAD = Buffer.from('复旦大学 eLearning 文件下载测试 🎓\n'.repeat(2000), 'utf8');
const BIG = Buffer.alloc(3 * 1024 * 1024, 0x41);

let flakyHits = 0;
let seenCookie = '';

const server: Server = createServer((req, res) => {
  const url = new URL(req.url ?? '/', 'http://localhost');
  seenCookie = String(req.headers.cookie ?? '');

  switch (url.pathname) {
    case '/small.pdf':
      res.writeHead(200, { 'Content-Type': 'application/pdf', 'Content-Length': PAYLOAD.length });
      res.end(PAYLOAD);
      return;

    case '/big.bin': {
      res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Content-Length': BIG.length });
      // 分块 + 故意放慢，让整个传输跨过多个进度节流窗口，
      // 这样才测得到「过程中确实有中间进度」。
      const CHUNK = 64 * 1024;
      let off = 0;
      const pump = (): void => {
        if (off >= BIG.length) {
          res.end();
          return;
        }
        res.write(BIG.subarray(off, off + CHUNK));
        off += CHUNK;
        setTimeout(pump, 15);
      };
      pump();
      return;
    }

    case '/flaky.txt': {
      flakyHits += 1;
      // 前两次直接断连，第三次成功——用来验证重试。
      if (flakyHits < 3) {
        res.destroy();
        return;
      }
      const body = Buffer.from('重试后成功', 'utf8');
      res.writeHead(200, { 'Content-Length': body.length });
      res.end(body);
      return;
    }

    case '/missing.pdf':
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('not found');
      return;

    case '/redirect.pdf':
      res.writeHead(302, { Location: '/small.pdf' });
      res.end();
      return;

    default:
      res.writeHead(404);
      res.end('no');
  }
});

await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
const port = (server.address() as { port: number }).port;
const base = `http://127.0.0.1:${port}`;
console.log(`本地测试服务器：${base}`);
console.log('=== 下载机制实测 ===\n');

function makeJar(): CookieJar {
  const jar = new CookieJar();
  jar.setFromResponse(base + '/', ['canvas_session=test-session-value; Path=/']);
  return jar;
}

async function download(
  items: Parameters<DownloadManager['run']>[0],
  opts: { into?: string; skipExisting?: boolean; signal?: AbortSignal } = {}
): Promise<{ progress: DownloadProgress; updates: DownloadProgress[] }> {
  const updates: DownloadProgress[] = [];
  const mgr = new DownloadManager({
    jar: makeJar(),
    root: opts.into ?? root,
    skipExisting: opts.skipExisting,
    signal: opts.signal,
    onProgress: (p) => updates.push(p),
  });
  const progress = await mgr.run(items);
  return { progress, updates };
}

// ---------------------------------------------------------------------------
console.log('[1] 小文件：内容与进度');
{
  const { progress, updates } = await download([
    { fileId: 1, url: `${base}/small.pdf`, relativePath: 'T/C/小.pdf', size: PAYLOAD.length, name: '小.pdf' },
  ]);

  check('任务完成', progress.state === 'done', progress.state);
  check('成功 1 个', progress.completed === 1, `completed=${progress.completed}`);
  check('无失败', progress.failed === 0, JSON.stringify(progress.errors));

  const dest = join(root, 'T/C/小.pdf');
  check('文件已落盘', existsSync(dest));
  const written = readFileSync(dest);
  check('内容逐字节一致', written.equals(PAYLOAD), `${written.length} vs ${PAYLOAD.length} 字节`);
  check('中文与 emoji 正确', written.toString('utf8').includes('🎓'));

  check('没有残留 .part 文件', !existsSync(dest + '.part'));
  check('进度回调有多次', updates.length >= 2, `${updates.length} 次`);
  check('末次回调标记完成', updates.at(-1)?.state === 'done');
  check('Cookie 已随请求发送', seenCookie.includes('canvas_session=test-session-value'), seenCookie.slice(0, 60));
}

console.log('\n[2] 大文件：流式写入与进度累积');
{
  const dir = join(tmp, 'big');
  const { progress, updates } = await download(
    [{ fileId: 2, url: `${base}/big.bin`, relativePath: 'big.bin', size: BIG.length, name: 'big.bin' }],
    { into: dir }
  );

  const dest = join(dir, 'big.bin');
  check('大文件完成', progress.completed === 1);
  check('大小正确', readFileSync(dest).length === BIG.length, `${BIG.length} 字节`);
  check('累计字节数正确', progress.bytesReceived === BIG.length, `${progress.bytesReceived}`);

  const mid = updates.filter((u) => u.currentReceived > 0 && u.currentReceived < BIG.length);
  check('过程中有中间进度', mid.length >= 1, `${mid.length} 次中间更新`);
}

console.log('\n[3] 同名同大小：跳过而非重下');
{
  const dir = join(tmp, 'skip');
  const item = { fileId: 3, url: `${base}/small.pdf`, relativePath: 'a.pdf', size: PAYLOAD.length, name: 'a.pdf' };

  const first = await download([item], { into: dir });
  check('首次下载', first.progress.completed === 1 && first.progress.skipped === 0);

  const second = await download([item], { into: dir });
  check('二次跳过', second.progress.skipped === 1, `skipped=${second.progress.skipped}`);
  check('不算失败', second.progress.failed === 0);

  // 大小不一致时应当重新下载
  const third = await download([{ ...item, size: 999 }], { into: dir });
  check('大小不符时重新下载', third.progress.completed === 1, `completed=${third.progress.completed}`);
}

console.log('\n[4] 路径逃逸防护');
{
  let threw = false;
  try {
    safeJoin(root, '../../evil.txt');
  } catch {
    threw = true;
  }
  check('safeJoin 拒绝 ../', threw);

  let threw2 = false;
  try {
    safeJoin(root, 'a/../../b');
  } catch {
    threw2 = true;
  }
  check('safeJoin 拒绝嵌套逃逸', threw2);

  // 绝对路径直接拒绝，两端行为一致（移动端同样抛错）。
  let threw3 = false;
  try {
    safeJoin(root, '/etc/passwd');
  } catch {
    threw3 = true;
  }
  check('safeJoin 拒绝绝对路径', threw3);

  let threw4 = false;
  try {
    safeJoin(root, 'C:\\Windows\\system32');
  } catch {
    threw4 = true;
  }
  check('safeJoin 拒绝盘符路径', threw4);

  const ok = safeJoin(root, 'T/C/x.pdf');
  check('正常路径可用', ok.startsWith(root), ok.slice(root.length));

  // 下载器层面也必须挡住
  const { progress } = await download([
    { fileId: 9, url: `${base}/small.pdf`, relativePath: '../escaped.pdf', size: PAYLOAD.length, name: 'escaped' },
  ]);
  check('下载器记为失败而非写出', progress.failed === 1 && progress.completed === 0);
  check('根目录外没有文件', !existsSync(join(tmp, 'escaped.pdf')));
}

console.log('\n[5] 失败与重试');
{
  const { progress } = await download([
    { fileId: 4, url: `${base}/missing.pdf`, relativePath: 'gone.pdf', size: 0, name: 'gone.pdf' },
  ]);
  check('404 记为失败', progress.failed === 1);
  check('错误里有路径', progress.errors[0]?.relativePath === 'gone.pdf');
  check('错误里有原因', (progress.errors[0]?.message ?? '').includes('404'), progress.errors[0]?.message);

  flakyHits = 0;
  const retry = await download([
    { fileId: 5, url: `${base}/flaky.txt`, relativePath: 'flaky.txt', size: 0, name: 'flaky.txt' },
  ]);
  check('瞬时故障重试后成功', retry.progress.completed === 1 && retry.progress.failed === 0, `尝试 ${flakyHits} 次`);
  check('重试次数符合预期', flakyHits === 3, `${flakyHits} 次`);
}

console.log('\n[6] 重定向跟随');
{
  const dir = join(tmp, 'redir');
  const { progress } = await download(
    [{ fileId: 6, url: `${base}/redirect.pdf`, relativePath: 'r.pdf', size: 0, name: 'r.pdf' }],
    { into: dir }
  );
  check('302 后仍能下载', progress.completed === 1, JSON.stringify(progress.errors));
  check('内容正确', readFileSync(join(dir, 'r.pdf')).equals(PAYLOAD));
}

console.log('\n[7] 多文件与取消');
{
  const dir = join(tmp, 'multi');
  const items = [
    { fileId: 11, url: `${base}/small.pdf`, relativePath: 'A/a.pdf', size: PAYLOAD.length, name: 'a.pdf' },
    { fileId: 12, url: `${base}/small.pdf`, relativePath: 'A/b.pdf', size: PAYLOAD.length, name: 'b.pdf' },
    { fileId: 13, url: `${base}/missing.pdf`, relativePath: 'B/c.pdf', size: 0, name: 'c.pdf' },
    { fileId: 14, url: `${base}/small.pdf`, relativePath: 'B/d.pdf', size: PAYLOAD.length, name: 'd.pdf' },
  ];
  const { progress } = await download(items, { into: dir });
  check('3 成功 1 失败', progress.completed === 3 && progress.failed === 1,
    `completed=${progress.completed} failed=${progress.failed}`);
  check('部分失败不影响其余', existsSync(join(dir, 'B/d.pdf')));
  check('总数记录正确', progress.total === 4);

  // 取消：已经取消的信号传入后应当不再开始下载
  const ac = new AbortController();
  ac.abort();
  const dir2 = join(tmp, 'cancel');
  const r = await download(
    [{ fileId: 15, url: `${base}/small.pdf`, relativePath: 'x.pdf', size: PAYLOAD.length, name: 'x.pdf' }],
    { into: dir2, signal: ac.signal }
  );
  check('取消后状态为 cancelled', r.progress.state === 'cancelled', r.progress.state);
  check('取消后没有下载任何文件', !existsSync(join(dir2, 'x.pdf')));
}

console.log('\n[8] 目录结构');
{
  const dir = join(tmp, 'layout');
  await download(
    [
      { fileId: 21, url: `${base}/small.pdf`, relativePath: '2026-2027 学年第一学期/CS100113.02 程序设计基础/课件/第1章/绪论.pdf', size: PAYLOAD.length, name: '绪论.pdf' },
      { fileId: 22, url: `${base}/small.pdf`, relativePath: '2026-2027 学年第一学期/CS100113.02 程序设计基础/大纲.pdf', size: PAYLOAD.length, name: '大纲.pdf' },
    ],
    { into: dir }
  );
  const baseDir = join(dir, '2026-2027 学年第一学期/CS100113.02 程序设计基础');
  check('中文目录已创建', existsSync(baseDir));
  check('多级子目录已创建', existsSync(join(baseDir, '课件/第1章/绪论.pdf')));
  check('课程根下文件已创建', existsSync(join(baseDir, '大纲.pdf')));

  const tree: string[] = [];
  const walk = (d: string, prefix = '') => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      tree.push(prefix + e.name);
      if (e.isDirectory()) walk(join(d, e.name), prefix + e.name + '/');
    }
  };
  walk(dir);
  check(
    '目录树符合「学期/课程/子文件夹」',
    tree.includes('2026-2027 学年第一学期/CS100113.02 程序设计基础/课件/第1章/绪论.pdf'),
    tree.join(' | ')
  );
}

// ---------------------------------------------------------------------------
server.close();
rmSync(tmp, { recursive: true, force: true });

console.log(`\n=== 结果：${passed}/${passed + failed} 项通过 ===`);
if (failed > 0) process.exit(1);
