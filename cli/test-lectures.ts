import assert from 'node:assert/strict';
import { createCipheriv, createHash, pbkdf2Sync } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { mkdtempSync, readdirSync, readFileSync, writeFileSync, statSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { createRequire } from 'node:module';
import initSqlJs from 'sql.js';
import { decodeIndex, derivePassword, digest, LectureEngine } from '../src/main/lectures/engine.ts';
import { LectureService, normalizeSource } from '../src/main/lectures/service.ts';
import { emptyWorkspace, recordChanges } from '../src/core/workspace.ts';
import { lectureKey } from '../src/core/lectures.ts';

const require = createRequire(import.meta.url);
const wasmPath = require.resolve('sql.js/dist/sql-wasm.wasm');
const SQL = await initSqlJs({ wasmBinary: Uint8Array.from(readFileSync(wasmPath)).buffer });
const password = derivePassword('20260000', 'fictional-test-password');
let checks = 0;
function check(value: unknown, label: string) { assert.ok(value, label); checks++; }
function encrypt(bytes: Uint8Array): Buffer {
  const salt = Buffer.from('12345678');
  const material = pbkdf2Sync(password, salt, 100000, 48, 'sha256');
  const cipher = createCipheriv('aes-256-cbc', material.subarray(0, 32), material.subarray(32));
  return Buffer.concat([Buffer.from('Salted__'), salt, cipher.update(bytes), cipher.final()]);
}
function shard(courseId: string | null, summary: string, count = 1): Buffer {
  const db = new SQL.Database();
  db.run(`CREATE TABLE courses(course_id TEXT PRIMARY KEY,title TEXT,teacher TEXT);
    CREATE TABLE lectures(sub_id TEXT PRIMARY KEY,course_id TEXT,sub_title TEXT,date TEXT,summary TEXT,transcript TEXT,processed_at TEXT,error_msg TEXT);
    CREATE TABLE ppt_pages(sub_id TEXT,page_num INTEGER,created_sec INTEGER,text TEXT);
    CREATE TABLE all_courses(course_id TEXT,term TEXT,title TEXT,teacher TEXT);`);
  if (courseId) {
    db.run('INSERT INTO courses VALUES(?,?,?)', [courseId, '同名课程', '测试教师']);
    for (let n = 0; n < count; n++) db.run('INSERT INTO lectures VALUES(?,?,?,?,?,?,?,?)', [`${courseId}-${n}`, courseId, `课次 ${n}`, '2026-10-01', `${summary}${n}`, '虚构转写', '2026-10-01T11:00:00Z', null]);
    db.run('INSERT INTO ppt_pages VALUES(?,?,?,?)', [`${courseId}-0`, 1, 60, '虚构 PPT']);
  } else for (const [id, term] of [['101', '2026 秋'], ['102', '2025 秋']]) db.run('INSERT INTO all_courses VALUES(?,?,?,?)', [id, term, '同名课程', '测试教师']);
  const bytes = encrypt(gzipSync(db.export(), { mtime: 0 } as any)); db.close(); return bytes;
}

const root = mkdtempSync(join(tmpdir(), 'lecture-contract-'));
let networkDown = false, failed = '', pause: (() => void) | undefined, release: (() => void) | undefined;
const blobs = new Map<string, Buffer>();
const files = new Map<string, { sha: string; bytes: Buffer }>();
const calls: string[] = [];
let revision = 0; const commitId = () => revision.toString(16).padStart(40,"0");
function publish(versions: [string, string | null, Buffer][]) {
  revision++; blobs.clear(); files.clear();
  const put = (path: string, bytes: Buffer) => {
    const sha = createHash('sha1').update(bytes).digest('hex'); blobs.set(sha, bytes); files.set(path, { sha, bytes });
  };
  for (const [name, , bytes] of versions) put(`data/shards/${name}`, bytes);
  put('data/icourse-index.enc', encrypt(Buffer.from(JSON.stringify({ version: 4, shards: versions.map(([name, id, bytes]) => ({ name, sha256: digest(bytes), size: bytes.length, ...(id ? { course_ids: [id] } : { bin: 'meta' }) })) }))));
}
const transport: typeof fetch = async (input) => {
  const url = String(input); calls.push(url);
  if (pause) { const entered = pause; pause = undefined; entered(); await new Promise<void>(r => { release = r; }); }
  if (networkDown) throw Error('offline');
  const path = url.split('/repos/test/notes/')[1];
  if (path?.startsWith('git/ref/heads/')) return Response.json({ object: { sha: commitId() } });
  if (path === `git/commits/${commitId()}`) return Response.json({ tree: { sha: 'b'.repeat(40) } });
  if (path === `git/trees/${'b'.repeat(40)}?recursive=1`) return Response.json({ tree: [...files].map(([path, file]) => ({ path, sha: file.sha, type: 'blob' })) });
  const sha = path?.replace('git/blobs/', '') ?? '';
  if (sha === failed) return new Response('failure', { status: 503 });
  return blobs.has(sha) ? new Response(Uint8Array.from(blobs.get(sha)!)) : new Response('', { status: 404 });
};
let failResources = false;
let account = 1, workspace = emptyWorkspace(1), eventId = 0;
const service = new LectureService({ root, wasmPath, workerPath: resolve('src/main/lectures/worker.ts'),
  protect: value => Buffer.from(value).toString('base64'), unprotect: value => Buffer.from(value, 'base64').toString(),
  isCurrent: id => id === account, fetch: transport, onUpdated() {},
  onResources(id, results) { if(failResources) throw Error("synthetic event write failure"); assert.equal(id, account); workspace = recordChanges(workspace, results, `batch-${eventId}`, new Date().toISOString(), () => `event-${++eventId}`); },
});
const input = { repository: 'test/notes', branch: 'data', studentId: '20260000', password: 'fictional-test-password', remember: true };
const meta = shard(null, '');
const first = shard('101', '初始摘要'), second = shard('102', '另一学期');
const initial: [string, string | null, Buffer][] = [['meta-0000.db.gz.enc', null, meta], ['shard-hot-0000.db.gz.enc', '101', first], ['shard-hot-0001.db.gz.enc', '102', second]];
const engine = new LectureEngine(wasmPath, 'performance');
try {
  publish(initial);
  check(normalizeSource('https://github.com/test/notes/', 'data').repository === 'test/notes', 'repository URL normalization');
  assert.throws(() => normalizeSource('../bad', 'data')); checks++;
  const indexBytes = files.get('data/icourse-index.enc')!.bytes;
  check(decodeIndex(indexBytes, password).version === 4, 'OpenSSL envelope interoperates with v4 index');
  assert.throws(() => decodeIndex(indexBytes, derivePassword('wrong', 'wrong'))); checks++;
  assert.throws(() => decodeIndex(encrypt(Buffer.from('{"version":99,"shards":[]}')), password), /版本/); checks++;
  let state = await service.connect(1, input);
  check(state.courses.length === 2 && state.bindings.length === 0, 'same title is not an automatic association');
  check(state.courses.find(c => c.id === '101')?.terms.includes('2026 秋'), 'catalog carries term identity');
  state = await service.bind(1, '101', 10);
  await service.bind(1, '102', 10);
  check(workspace.changes.length === 0, 'first course binding establishes silent baseline');
  const page = await service.list(1, 10);
  check(page.total === 2 && !('summary' in page.items[0]), 'multi-source list has metadata only');
  const ref = page.items.find(i => i.icourseCourseId === '101')!;
  check((await service.detail(1, ref)).pages[0].text === '虚构 PPT', 'lecture supplies transcript and OCR pages');
  await service.read(1, ref);
  check((await service.list(1, 10)).items.find(i => i.icourseCourseId === '101')?.read, 'read is persisted per content hash');
  const folder = join(root, '1', state.sourceId);
  const modified = Object.fromEntries(readdirSync(folder).map(name=>[name, statSync(join(folder,name)).mtimeMs]));
  calls.length = 0;
  await service.sync(1);
  check(calls.length === 1, 'healthy same-commit check only resolves the upstream ref');
  check(Object.entries(modified).every(([name,time])=>statSync(join(folder,name)).mtimeMs === time), 'healthy check performs zero shard or metadata writes');
  check(!calls.some(url => initial.some(([, , bytes]) => url.endsWith(createHash('sha1').update(bytes).digest('hex')))), 'unchanged shards are not downloaded');
  check(workspace.changes.length === 0, 'repeated sync is quiet');
  const update = shard('101', '更新摘要', 2);
  publish([initial[0], ['shard-hot-0000.db.gz.enc', '101', update], initial[2]]);
  failResources = true;
  check(!!(await service.sync(1)).error, 'event persistence failure remains visible');
  failResources = false; calls.length=0;
  await service.sync(1);
  check(calls.length === 1, 'same-commit event recovery does not download shards');
  check(workspace.changes.length === 2, 'new lecture and changed summary each emit once');
  check(workspace.changes.every(c => c.after.length === 64 && !c.after.includes('摘要')), 'change baseline never stores full text');
  check((await service.list(1, 10)).items.find(i => i.lectureId === ref.lectureId)?.updated, 'updated read version is shown unread');
  await service.sync(1);
  check(workspace.changes.length === 2, 'updated version also deduplicates');
  await service.bind(1, '101', 11);
  check(workspace.changes.length === 2 && (await service.list(1, 10)).total === 1 && (await service.list(1, 11)).total === 2, 'remapping is silent and one external source has one destination');
  networkDown = true;
  check(!!(await service.sync(1)).error && (await service.detail(1, ref)).summary.startsWith('更新摘要'), 'offline sync preserves last good body');
  service.reset();
  check(!(await service.state(1)).locked && (await service.list(1, 11)).total === 2, 'remembered key opens offline encrypted cache after restart');
  await assert.rejects(service.connect(1, { ...input, password: 'incorrect' })); checks++;
  check((await service.detail(1, ref)).summary.startsWith('更新摘要'), 'failed reconnect preserves active source');
  networkDown = false;
  const failedUpdate = shard('101', '失败更新');
  publish([initial[0], ['shard-hot-0000.db.gz.enc', '101', failedUpdate], initial[2]]);
  failed = files.get('data/shards/shard-hot-0000.db.gz.enc')!.sha;
  check(!!(await service.sync(1)).error, 'partial sync surfaces failure');
  check((await service.detail(1, ref)).summary.startsWith('更新摘要') && workspace.changes.length === 2, 'failed shard neither replaces content nor advances baseline');
  state = await service.connect(1, input);
  check(!!state.error && (await service.detail(1, ref)).summary.startsWith('更新摘要'), 'partial reconnect hydrates preserved shards');
  failed = '';
  check(!(await service.sync(1)).error && (await service.detail(1, ref)).summary.startsWith('失败更新'), 'same-commit failed shard is retried');
  publish([initial[0], ['shard-cold-0000.db.gz.enc', '101', update], initial[2]]);
  await service.sync(1); service.reset();
  check((await service.list(1, 11)).total === 2 && (await service.detail(1, ref)).summary.startsWith('更新摘要'), 'hot/cold shard move survives restart without duplicates');
  const registry = JSON.parse(readFileSync(join(root, '1', 'connection.json'), 'utf8'));
  const stored = registry.sources[registry.active];
  check(stored.previousHashes.every((h: string)=>existsSync(join(folder,`${h}.enc`))), 'rollback manifest blobs survive cleanup');
  check(!Object.hasOwn(stored.shards, 'shard-hot-0000.db.gz.enc'), 'retired shards are removed from active manifest');
  check(readdirSync(join(root, '1', state.sourceId)).every(name => name.endsWith('.enc') || name.endsWith('.enc.index') || name === 'state.json'), 'no plaintext SQLite or note files are written');
  assert.ok(!JSON.stringify(stored).includes('fictional-test-password')); checks++;
  const indexPath = join(folder, `${stored.indexHash}.enc`);
  writeFileSync(indexPath, 'synthetic corruption'); service.reset();
  check(!!(await service.state(1)).error && (await service.detail(1, ref)).summary.startsWith('更新摘要'), 'damaged manifest preserves readable cached bodies');
  check(!(await service.sync(1)).error && digest(readFileSync(indexPath)) === stored.indexHash, 'same-commit recovery repairs a corrupt manifest');
  service.reset();
  check(!(await service.state(1)).error, 'repaired manifest survives another restart');
  const before = readFileSync(join(root, '1', 'connection.json'), 'utf8');
  const entered = new Promise<void>(r => { pause = r; });
  const flight = service.sync(1);
  await entered; service.reset(); account = 2; release!();
  await assert.rejects(flight, /切换|取消|账号/); checks++;
  check(readFileSync(join(root, '1', 'connection.json'), 'utf8') === before && !(await service.state(2)).configured, 'account change cancels old writes and isolates new account');
  await assert.rejects(service.detail(1, ref)); checks++;
  const large = shard('performance', '课堂摘要', 5000);
  await engine.load('large.db.gz.enc', large, password, digest(large));
  const started = performance.now(), result = engine.list(['performance'], '课次 4999');
  check(result.total === 1 && performance.now() - started < 1000, '5000-lecture search stays bounded');
  check(engine.list(['performance']).items.length === 50 && engine.list(['performance'], '', 4950).items.length === 50, 'large lists page at 50');
  const corrupt = Buffer.from(large); corrupt[40] ^= 1;
  await assert.rejects(engine.load('large.db.gz.enc', corrupt, password, digest(large))); checks++;
  check(engine.list(['performance']).total === 5000, 'invalid shard retains last working database');
  console.log(`lectures: ${checks} checks passed; synthetic encrypted fixtures only`);
} finally { service.dispose(); engine.close(); }
