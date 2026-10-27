import { Worker } from 'node:worker_threads';
import { createHash, randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import type { Snapshot } from '../../core/types.ts';
import type { ResourceResult } from '../../core/workspace.ts';
import { DEFAULT_LECTURE_REPOSITORY, lectureKey, type LectureBinding, type LectureBody, type LectureConnectInput,
  type LectureConnection, type LectureCourse, type LectureItem, type LecturePage, type LectureRef } from '../../core/lectures.ts';
import type { LectureIndex, ShardEntry } from './engine.ts';

interface Options {
  root: string; workerPath: string; wasmPath: string;
  protect: (value: string) => string; unprotect: (value: string) => string;
  isCurrent: (account: number) => boolean; onUpdated: () => void;
  onResources: (account: number, results: ResourceResult[]) => void | Promise<void>;
  demoSnapshot?: () => Snapshot | null;
  /** Deterministic test transport; production uses the platform fetch implementation. */
  fetch?: typeof fetch;
}
interface Stored {
  version: 1; account: number; configured: boolean; repository: string; branch: string; sourceId: string;
  secret?: string; bindings: LectureBinding[]; generations: Record<string, string>;
  reads: Record<string, string>; shards: Record<string, { hash: string; courseIds: string[] }>;
  indexHash?: string; lastSynced?: string;
}
interface Context {
  account: number; stored: Stored; worker: Rpc; epoch: number; abort: AbortController;
  password?: string; token?: string; courses: LectureCourse[]; error?: string;
  flight?: Promise<LectureConnection>; demo?: boolean;
}
const hash = (value: string | Uint8Array) => createHash('sha256').update(value).digest('hex');
const message = (error: unknown) => error instanceof Error ? error.message : '课堂笔记同步失败';
export function normalizeSource(repository: string, branch: string): { repository: string; branch: string; sourceId: string } {
  const normalized = repository.trim().replace(/^https:\/\/github\.com\//i, '').replace(/\/?$/, '').replace(/\.git$/, '');
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(normalized) || normalized.includes('..')) throw new Error('请输入 GitHub 的 用户名/仓库名');
  const ref = branch.trim() || 'data';
  if (ref.length > 200 || /[\s~^:?*\[\\]/.test(ref) || ref.includes('..') || ref.startsWith('/') || ref.endsWith('/')) throw new Error('分支名称无效');
  return { repository: normalized, branch: ref, sourceId: hash(`${normalized.toLowerCase()}\n${ref}`).slice(0, 32) };
}
class Rpc {
  private worker: Worker; private id = 0; private dead = false;
  private pending = new Map<number, { resolve: (value: any) => void; reject: (error: Error) => void }>();
  constructor(path: string, wasmPath: string, sourceId: string) {
    this.worker = new Worker(path, { workerData: { wasmPath, sourceId } });
    this.worker.on('message', (reply: { id: number; value?: unknown; error?: string }) => {
      const p = this.pending.get(reply.id); if (!p) return; this.pending.delete(reply.id);
      if (reply.error) p.reject(new Error(reply.error)); else p.resolve(reply.value);
    });
    this.worker.on('error', error => this.fail(error));
    this.worker.on('exit', () => this.fail(new Error('课堂内容工作线程已结束')));
  }
  call<T>(method: string, ...args: unknown[]): Promise<T> {
    if (this.dead) return Promise.reject(new Error('课堂内容操作已取消'));
    return new Promise<T>((resolve, reject) => { const id = ++this.id; this.pending.set(id, { resolve, reject }); this.worker.postMessage({ id, method, args }); });
  }
  private fail(error: Error) { this.dead = true; for (const p of this.pending.values()) p.reject(error); this.pending.clear(); }
  close() { this.fail(new Error('账号或笔记源已切换，操作已取消')); void this.worker.terminate(); }
}

export class LectureService {
  private contexts = new Map<number, Context>();
  private loading = new Map<number, Promise<Context>>();
  private epoch = 0;
  private connecting = new Set<number>();
  private live = new Set<Context>();
  private options: Options;
  constructor(options: Options) { this.options = options; }
  private accountDir(account: number) {
    if (!Number.isSafeInteger(account) || account < 0) throw new Error('账号无效');
    return join(this.options.root, String(account));
  }
  private guard(ctx: Context) {
    if (ctx.epoch !== this.epoch || ctx.abort.signal.aborted || !this.options.isCurrent(ctx.account)) throw new Error('账号或笔记源已切换，操作已取消');
  }
  private folder(ctx: Context) { return join(this.accountDir(ctx.account), ctx.stored.sourceId); }
  private blob(ctx: Context, digest: string) {
    if (!/^[a-f0-9]{64}$/.test(digest)) throw new Error('笔记缓存索引无效');
    return join(this.folder(ctx), `${digest}.enc`);
  }
  private atomic(ctx: Context, path: string, data: string | Uint8Array) {
    this.guard(ctx); mkdirSync(this.folder(ctx), { recursive: true });
    const temporary = `${path}.${randomUUID()}.tmp`;
    try { writeFileSync(temporary, data, { flush: true }); this.guard(ctx); renameSync(temporary, path); }
    finally { if (existsSync(temporary)) unlinkSync(temporary); }
  }
  private persist(ctx: Context) {
    if (ctx.demo) return;
    const value = JSON.stringify(ctx.stored);
    this.atomic(ctx, join(this.folder(ctx), 'state.json'), value);
    this.atomic(ctx, join(this.accountDir(ctx.account), 'connection.json'), value);
  }
  private blank(account: number, repository = DEFAULT_LECTURE_REPOSITORY, branch = 'data'): Stored {
    return { version: 1, account, configured: false, ...normalizeSource(repository, branch), bindings: [], generations: {}, reads: {}, shards: {} };
  }
  private loadStored(path: string, account: number): Stored | undefined {
    if (!existsSync(path)) return;
    const s = JSON.parse(readFileSync(path, 'utf8')) as Stored;
    if (s.version !== 1 || s.account !== account || !Array.isArray(s.bindings) || !s.reads || !s.shards || !s.generations ||
        normalizeSource(s.repository, s.branch).sourceId !== s.sourceId) throw new Error('本地课堂笔记配置格式异常，原文件已保留');
    return s;
  }
  private make(account: number, stored: Stored): Context {
    const ctx: Context = { account, stored, epoch: this.epoch, abort: new AbortController(), courses: [],
      worker: new Rpc(this.options.workerPath, this.options.wasmPath, stored.sourceId) };
    this.live.add(ctx); return ctx;
  }
  private close(ctx: Context) { ctx.abort.abort(); ctx.worker.close(); ctx.password = undefined; ctx.token = undefined; this.live.delete(ctx); }
  private async context(account: number): Promise<Context> {
    if (!this.options.isCurrent(account)) throw new Error('请先登录当前账号');
    const existing = this.contexts.get(account); if (existing) return existing;
    const pending = this.loading.get(account); if (pending) return pending;
    const epoch = this.epoch;
    const promise = (async () => {
      const demo = this.options.demoSnapshot?.();
      const stored = demo ? this.blank(account, 'demo/classroom') : this.loadStored(join(this.accountDir(account), 'connection.json'), account) ?? this.blank(account);
      const ctx = this.make(account, stored);
      try {
        if (demo) {
          ctx.demo = true; ctx.stored.configured = true; ctx.password = 'demo';
          await ctx.worker.call('demo', demo.courses);
          ctx.stored.bindings = demo.courses.slice(0, 4).map(c => ({ icourseCourseId: `demo-${c.id}`, canvasCourseId: c.id }));
          ctx.stored.generations = Object.fromEntries(ctx.stored.bindings.map(b => [b.icourseCourseId, 'demo']));
          ctx.courses = await ctx.worker.call('courses');
        } else if (stored.configured && stored.secret) {
          try {
            const secret = JSON.parse(this.options.unprotect(stored.secret)) as { password: string; token?: string };
            if (!/^[a-f0-9]{64}$/.test(secret.password)) throw new Error('解锁信息无效');
            ctx.password = secret.password; ctx.token = secret.token;
            await this.hydrate(ctx);
          } catch (error) { ctx.error = `需要重新解锁课堂笔记：${message(error)}`; ctx.password = undefined; }
        }
        this.guard(ctx); if (epoch !== this.epoch) throw new Error('账号已切换');
        this.contexts.set(account, ctx); return ctx;
      } catch (error) { this.close(ctx); throw error; }
    })();
    this.loading.set(account, promise);
    try { return await promise; } finally { if (this.loading.get(account) === promise) this.loading.delete(account); }
  }
  private public(ctx: Context): LectureConnection {
    return { configured: ctx.stored.configured, repository: ctx.stored.repository, branch: ctx.stored.branch, sourceId: ctx.stored.sourceId,
      locked: !ctx.password, remembered: !!ctx.stored.secret, syncing: !!ctx.flight, lastSynced: ctx.stored.lastSynced,
      error: ctx.error, courses: ctx.courses, bindings: ctx.stored.bindings };
  }
  async state(account: number): Promise<LectureConnection> { return this.public(await this.context(account)); }
  private async hydrate(ctx: Context) {
    if (!ctx.password) return;
    if (ctx.stored.indexHash) await ctx.worker.call('index', readFileSync(this.blob(ctx, ctx.stored.indexHash)), ctx.password);
    const errors: string[] = [];
    for (const [name, shard] of Object.entries(ctx.stored.shards)) {
      this.guard(ctx);
      try { await ctx.worker.call('load', name, readFileSync(this.blob(ctx, shard.hash)), ctx.password, shard.hash); }
      catch { errors.push(name); }
    }
    ctx.courses = await ctx.worker.call('courses'); this.guard(ctx);
    if (errors.length) ctx.error = `${errors.length} 个本地分片无法读取，请重试同步；其余缓存仍可使用`;
  }
  async connect(account: number, input: LectureConnectInput): Promise<LectureConnection> {
    if (this.connecting.has(account)) throw new Error('正在连接课堂笔记，请稍候');
    const current = await this.context(account);
    if (this.connecting.has(account)) throw new Error('正在连接课堂笔记，请稍候');
    this.guard(current);
    if (current.demo) return this.public(current);
    const source = normalizeSource(input.repository, input.branch);
    if (!input.studentId.trim() || !input.password) throw new Error('请输入生成笔记时使用的学号和 UIS 密码');
    const cached = this.loadStored(join(this.accountDir(account), source.sourceId, 'state.json'), account);
    const stored = cached ?? this.blank(account, source.repository, source.branch);
    const candidate = this.make(account, { ...stored, configured: true });
    this.connecting.add(account);
    try {
      candidate.password = await candidate.worker.call('derive', input.studentId.trim(), input.password);
      candidate.token = input.token?.trim() || undefined;
      if (candidate.stored.indexHash) {
        try { await this.hydrate(candidate); } catch { this.guard(candidate); /* A new upstream password may replace the old cache key. */ }
      }
      // Validate credentials against cached encrypted index before allowing offline unlock.
      let offline = false;
      try { await this.download(candidate, false); }
      catch (error) {
        if (!candidate.stored.indexHash) throw error;
        await this.hydrate(candidate);
        candidate.error = `已解锁本地缓存；在线同步失败：${message(error)}`; offline = true;
      }
      this.guard(candidate);
      candidate.stored.secret = input.remember ? this.options.protect(JSON.stringify({ password: candidate.password, token: candidate.token })) : undefined;
      this.persist(candidate);
      this.close(current);
      this.contexts.set(account, candidate);
      if (!offline) try { await this.emitResources(candidate); } catch (error) { this.guard(candidate); candidate.error = `笔记已连接，变化记录保存失败：${message(error)}`; }
      this.options.onUpdated(); return this.public(candidate);
    } catch (error) { this.close(candidate); throw error; }
    finally { this.connecting.delete(account); }
  }
  async disconnect(account: number): Promise<LectureConnection> {
    if (this.connecting.has(account)) throw new Error('正在连接课堂笔记，请稍候再断开');
    const ctx = await this.context(account);
    if (ctx.demo) return this.public(ctx);
    const next = { ...ctx.stored, configured: false, secret: undefined };
    this.atomic(ctx, join(this.folder(ctx), 'state.json'), JSON.stringify(next));
    this.atomic(ctx, join(this.accountDir(account), 'connection.json'), JSON.stringify(next));
    this.close(ctx); this.contexts.delete(account); this.options.onUpdated();
    return this.state(account);
  }
  private async bytes(ctx: Context, path: string, binary = false, limit = 128 * 1024 * 1024): Promise<Uint8Array> {
    this.guard(ctx);
    const headers: Record<string, string> = { Accept: binary ? 'application/vnd.github.raw+json' : 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' };
    if (ctx.token) headers.Authorization = `Bearer ${ctx.token}`;
    let response: Response;
    try { response = await (this.options.fetch ?? fetch)(`https://api.github.com/repos/${ctx.stored.repository}/${path}`, {
      headers, signal: AbortSignal.any([ctx.abort.signal, AbortSignal.timeout(45000)]), redirect: 'error' }); }
    catch { this.guard(ctx); throw new Error('无法连接 GitHub，请检查网络后重试'); }
    if (!response.ok) throw new Error(response.status === 404 ? '找不到数据分支或笔记文件；私有仓库请提供只读令牌' :
      response.status === 401 ? 'GitHub 令牌无效，请重新配置' : response.status === 403 || response.status === 429 ? 'GitHub 请求受限，请稍后重试或配置只读令牌' : `GitHub 同步失败（${response.status}）`);
    if (Number(response.headers.get('content-length')) > limit) throw new Error('笔记文件超过支持的大小');
    const reader = response.body?.getReader(); if (!reader) throw new Error('GitHub 返回空响应');
    const chunks: Uint8Array[] = []; let size = 0;
    try { while (true) { const { done, value } = await reader.read(); if (done) break; size += value.length; if (size > limit) throw new Error('笔记文件超过支持的大小'); chunks.push(value); } }
    finally { await reader.cancel(); }
    this.guard(ctx); return Buffer.concat(chunks);
  }
  private async json<T>(ctx: Context, path: string): Promise<T> {
    try { return JSON.parse(Buffer.from(await this.bytes(ctx, path, false, 16 * 1024 * 1024)).toString()) as T; }
    catch (error) { if (error instanceof SyntaxError) throw new Error('GitHub 返回的数据格式无效'); throw error; }
  }
  private async download(ctx: Context, publish: boolean) {
    const ref = await this.json<{ object: { sha: string } }>(ctx, `git/ref/heads/${encodeURIComponent(ctx.stored.branch)}`);
    if (!/^[a-f0-9]{40}$/.test(ref.object?.sha)) throw new Error('GitHub 分支格式无效');
    const commit = await this.json<{ tree: { sha: string } }>(ctx, `git/commits/${ref.object.sha}`);
    if (!/^[a-f0-9]{40}$/.test(commit.tree?.sha)) throw new Error('GitHub 提交格式无效');
    const tree = await this.json<{ truncated?: boolean; tree: { path: string; sha: string; type: string }[] }>(ctx, `git/trees/${commit.tree.sha}?recursive=1`);
    if (tree.truncated || !Array.isArray(tree.tree)) throw new Error('GitHub 文件目录过大或不完整');
    const entries = new Map(tree.tree.filter(e => e.type === 'blob').map(e => [e.path, e.sha]));
    const indexBlob = entries.get('data/icourse-index.enc');
    if (!indexBlob || !/^[a-f0-9]{40}$/.test(indexBlob)) throw new Error('未找到版本 4 的加密笔记索引，请先运行订阅仓库');
    const encrypted = await this.bytes(ctx, `git/blobs/${indexBlob}`, true, 4 * 1024 * 1024);
    const index = await ctx.worker.call<LectureIndex>('index', encrypted, ctx.password);
    this.guard(ctx);
    const failures: string[] = [], successCourses = new Set<string>();
    // Cache successful shards individually; unavailable or invalid shards leave last good bytes untouched.
    for (const shard of index.shards) {
      this.guard(ctx);
      try {
        let bytes: Uint8Array;
        const cache = this.blob(ctx, shard.sha256);
        if (existsSync(cache)) bytes = readFileSync(cache);
        else bytes = new Uint8Array();
        if (bytes.length !== shard.size || hash(bytes) !== shard.sha256) {
          const sha = entries.get(`data/shards/${shard.name}`);
          if (!sha || !/^[a-f0-9]{40}$/.test(sha)) throw new Error('提交中缺少分片');
          bytes = await this.bytes(ctx, `git/blobs/${sha}`, true);
        }
        if (bytes.length !== shard.size) throw new Error('分片大小不符');
        const courses = await ctx.worker.call<string[]>('load', shard.name, bytes, ctx.password, shard.sha256);
        this.guard(ctx); this.atomic(ctx, cache, bytes);
        ctx.stored.shards[shard.name] = { hash: shard.sha256, courseIds: courses };
        for (const id of courses) successCourses.add(id);
      } catch (error) {
        this.guard(ctx); failures.push(`${shard.name}: ${message(error)}`);
      }
    }
    if (index.shards.length && failures.length === index.shards.length) throw new Error(`所有笔记分片读取失败：${failures[0]}`);
    if (!failures.length) {
      const names = new Set(index.shards.map(shard => shard.name));
      await ctx.worker.call('retain', [...names]); this.guard(ctx);
      ctx.stored.shards = Object.fromEntries(Object.entries(ctx.stored.shards).filter(([name]) => names.has(name)));
    }
    const indexHash = hash(encrypted); this.atomic(ctx, this.blob(ctx, indexHash), encrypted); ctx.stored.indexHash = indexHash;
    ctx.stored.lastSynced = new Date().toISOString();
    ctx.courses = await ctx.worker.call('courses'); this.guard(ctx);
    ctx.error = failures.length ? `${failures.length} 个分片同步失败，已保留旧内容。${failures[0]}` : undefined;
    if (publish) { this.persist(ctx); await this.emitResources(ctx, successCourses); }
  }
  private async emitResources(ctx: Context, successCourses?: Set<string>) {
    const resources: ResourceResult[] = [];
    for (const binding of ctx.stored.bindings) {
      const items = await ctx.worker.call<{ ref: LectureRef; title: string; hash: string }[]>('resources', [binding.icourseCourseId]);
      resources.push({ courseId: binding.canvasCourseId, kind: 'lecture',
        baselineKey: `${ctx.stored.sourceId}:${binding.icourseCourseId}:${ctx.stored.generations[binding.icourseCourseId]}`,
        status: !successCourses || successCourses.has(binding.icourseCourseId) ? 'success' : 'failed',
        items: items.map(i => ({ id: lectureKey(i.ref), title: i.title, value: i.hash })) });
    }
    this.guard(ctx); await this.options.onResources(ctx.account, resources); this.guard(ctx);
  }
  async sync(account: number): Promise<LectureConnection> {
    const ctx = await this.context(account);
    if (!ctx.stored.configured || ctx.demo) return this.public(ctx);
    if (!ctx.password) { ctx.error = '课堂笔记已锁定，请在设置中解锁'; return this.public(ctx); }
    if (ctx.flight) return ctx.flight;
    ctx.flight = (async () => {
      try { await this.download(ctx, true); }
      catch (error) { this.guard(ctx); ctx.error = message(error); }
      finally { ctx.flight = undefined; if (ctx.epoch === this.epoch && !ctx.abort.signal.aborted && this.options.isCurrent(account)) this.options.onUpdated(); }
      return this.public(ctx);
    })();
    this.options.onUpdated(); return ctx.flight;
  }
  async bind(account: number, icourseCourseId: string, canvasCourseId: number | null): Promise<LectureConnection> {
    const ctx = await this.context(account); this.guard(ctx);
    const parsed = icourseCourseId.match(/(?:course(?:\/|=)|course_id=)(\d+)/i)?.[1] ?? icourseCourseId.trim();
    if (!ctx.courses.some(c => c.id === parsed)) throw new Error('尚未下载该 iCourse 课程，请先同步或检查课程链接');
    if (canvasCourseId !== null && (!Number.isSafeInteger(canvasCourseId) || canvasCourseId < 0)) throw new Error('目标课程无效');
    const old = ctx.stored;
    const existing = old.bindings.find(b => b.icourseCourseId === parsed);
    if ((existing?.canvasCourseId ?? null) === canvasCourseId) return this.public(ctx);
    ctx.stored = { ...old, bindings: old.bindings.filter(b => b.icourseCourseId !== parsed), generations: { ...old.generations, [parsed]: randomUUID() } };
    if (canvasCourseId !== null) ctx.stored.bindings.push({ icourseCourseId: parsed, canvasCourseId });
    try { this.persist(ctx); } catch (error) { ctx.stored = old; throw error; }
    try { await this.emitResources(ctx); } catch (error) { this.guard(ctx); ctx.error = `课程已关联，变化记录保存失败：${message(error)}`; }
    this.options.onUpdated(); return this.public(ctx);
  }
  private async available(account: number): Promise<Context> {
    const ctx = await this.context(account); this.guard(ctx);
    if (!ctx.stored.configured || !ctx.password) throw new Error('请先在设置中连接并解锁课堂笔记');
    return ctx;
  }
  private decorate<T extends LectureItem>(ctx: Context, item: T): T {
    const previous = ctx.stored.reads[lectureKey(item)];
    return { ...item, read: previous === (item.summaryHash || 'empty'), updated: !!previous && previous !== (item.summaryHash || 'empty') };
  }
  async list(account: number, courseId: number, query = '', offset = 0): Promise<LecturePage> {
    const ctx = await this.available(account);
    const ids = ctx.stored.bindings.filter(b => b.canvasCourseId === courseId).map(b => b.icourseCourseId);
    if (!Number.isSafeInteger(offset) || offset < 0 || query.length > 500) throw new Error('课堂笔记查询无效');
    const page = await ctx.worker.call<LecturePage>('list', ids, query, offset); this.guard(ctx);
    return { ...page, items: page.items.map(i => this.decorate(ctx, i)) };
  }
  async detail(account: number, ref: LectureRef): Promise<LectureBody> {
    const ctx = await this.available(account);
    if (ref.sourceId !== ctx.stored.sourceId || !ctx.stored.bindings.some(b => b.icourseCourseId === ref.icourseCourseId)) throw new Error('这条笔记未关联当前账号的课程');
    const body = await ctx.worker.call<LectureBody>('body', ref); this.guard(ctx); return this.decorate(ctx, body);
  }
  async read(account: number, ref: LectureRef): Promise<true> {
    const body = await this.detail(account, ref), ctx = await this.available(account), old = ctx.stored;
    this.guard(ctx);
    if (ref.sourceId !== ctx.stored.sourceId || !ctx.stored.bindings.some(b => b.icourseCourseId === ref.icourseCourseId)) throw new Error('笔记源或课程关联已调整，请重新打开笔记');
    ctx.stored = { ...old, reads: { ...old.reads, [lectureKey(ref)]: body.summaryHash || 'empty' } };
    try { this.persist(ctx); } catch (error) { ctx.stored = old; throw error; }
    this.options.onUpdated(); return true;
  }
  reset(): void {
    this.epoch++; for (const ctx of this.live) this.close(ctx);
    this.contexts.clear(); this.loading.clear(); this.connecting.clear();
  }
  dispose(): void { this.reset(); }
}
