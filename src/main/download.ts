/**
 * 课程文件下载。
 *
 * 在主进程里跑：只有这里能写磁盘、也只有在 Node 里才能做流式下载
 * （几百 MB 的课件视频不能整个读进内存）。
 *
 * 几个刻意的设计：
 *  - **先写 .part 再改名**：下载中断不会留下一个看起来完整、实际残缺的文件；
 *  - **同名同大小直接跳过**：重复点「下载本课全部」不会重复拉取；
 *  - **路径逃逸防护**：Canvas 理论上不可能给出 `../`，但落盘前仍要再确认一次
 *    最终路径确实在下载根目录之内；
 *  - **进度节流**：每个数据块都发一次 IPC 会把渲染进程淹掉，按时间合并。
 */

import { createWriteStream } from 'node:fs';
import { mkdir, rename, stat, unlink } from 'node:fs/promises';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';

import type { CookieJar } from '../core/cookies.ts';

const DEFAULT_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

/** 进度上报的最小间隔，避免把 IPC 打满。 */
const PROGRESS_INTERVAL_MS = 180;

/** 单个文件的失败重试次数。 */
const MAX_RETRIES = 2;

export interface DownloadItem {
  fileId: number;
  /** 带 verifier 的限时地址，必须来自本轮接口响应。 */
  url: string;
  /** 相对下载根目录的路径（已净化、已去重）。 */
  relativePath: string;
  /** 接口给的大小，用于判断是否需要重新下载；未知则填 0。 */
  size: number;
  name: string;
}

/** Node 的 fetch 只抛出笼统的 "fetch failed"，真正的原因在 cause 里。 */
function describeError(err: unknown): string {
  if (!(err instanceof Error)) return String(err);
  const cause = (err as { cause?: unknown }).cause;
  if (cause instanceof Error && cause.message && cause.message !== err.message) {
    const code = (cause as { code?: string }).code;
    return `${err.message}（${cause.message}${code ? ` / ${code}` : ''}）`;
  }
  if (cause && typeof cause === 'object' && 'code' in cause) {
    return `${err.message}（${String((cause as { code?: unknown }).code)}）`;
  }
  return err.message;
}

export interface DownloadError {
  relativePath: string;
  message: string;
}

export interface DownloadProgress {
  total: number;
  completed: number;
  skipped: number;
  failed: number;
  /** 正在下载的文件名。 */
  currentName: string;
  /** 整个任务已接收的字节数与总字节数（总数为 0 表示未知）。 */
  bytesReceived: number;
  bytesTotal: number;
  /** 当前文件已接收的字节数与总字节数。 */
  currentReceived: number;
  currentTotal: number;
  errors: DownloadError[];
  state: 'running' | 'done' | 'cancelled';
}

/**
 * 把相对路径安全地拼到根目录下。
 *
 * 绝对路径（以 / 开头，或 Windows 的盘符）直接拒绝，而不是当成相对路径处理——
 * `path.resolve` 会把 `/etc/passwd` 解析成根目录外，但那样只会得到一个
 * 含糊的「越界」错误；显式拒绝更能说明问题出在哪。
 *
 * 移动端 `lib/platform/downloads.dart` 的 safeJoin 行为与此一致。
 */
export function safeJoin(root: string, relativePath: string): string {
  if (relativePath.startsWith('/') || /^[A-Za-z]:/.test(relativePath)) {
    throw new Error(`下载路径不能是绝对路径：${relativePath}`);
  }
  const rootAbs = resolve(root);
  const finalAbs = resolve(rootAbs, relativePath);
  const rel = relative(rootAbs, finalAbs);
  if (rel.startsWith('..') || rel === '' || resolve(rootAbs, rel) !== finalAbs) {
    throw new Error(`路径越出下载目录：${relativePath}`);
  }
  return finalAbs;
}

export interface DownloadOptions {
  jar: CookieJar;
  root: string;
  onProgress: (p: DownloadProgress) => void;
  /** 上层用来取消；取消后已完成的部分文件会保留为 .part。 */
  signal?: AbortSignal;
  /** 已存在且大小一致时是否跳过，默认 true。 */
  skipExisting?: boolean;
}

export class DownloadManager {
  private readonly opts: DownloadOptions;
  private readonly progress: DownloadProgress;
  private lastEmit = 0;
  private cancelled = false;

  constructor(opts: DownloadOptions) {
    this.opts = opts;
    this.progress = {
      total: 0,
      completed: 0,
      skipped: 0,
      failed: 0,
      currentName: '',
      bytesReceived: 0,
      bytesTotal: 0,
      currentReceived: 0,
      currentTotal: 0,
      errors: [],
      state: 'running',
    };
  }

  private emit(force = false): void {
    const now = Date.now();
    if (!force && now - this.lastEmit < PROGRESS_INTERVAL_MS) return;
    this.lastEmit = now;
    this.opts.onProgress({ ...this.progress, errors: [...this.progress.errors] });
  }

  cancel(): void {
    this.cancelled = true;
  }

  async run(items: DownloadItem[]): Promise<DownloadProgress> {
    this.progress.total = items.length;
    this.progress.bytesTotal = items.reduce((s, i) => s + (i.size > 0 ? i.size : 0), 0);
    this.emit(true);

    for (const item of items) {
      if (this.cancelled || this.opts.signal?.aborted) break;

      this.progress.currentName = item.name;
      this.progress.currentReceived = 0;
      this.progress.currentTotal = item.size > 0 ? item.size : 0;
      this.emit(true);

      try {
        const outcome = await this.fetchOne(item);
        if (outcome === 'skipped') this.progress.skipped += 1;
        else this.progress.completed += 1;
      } catch (err) {
        if (this.cancelled || this.opts.signal?.aborted) break;
        this.progress.failed += 1;
        this.progress.errors.push({
          relativePath: item.relativePath,
          message: describeError(err),
        });
      }
      this.emit(true);
    }

    this.progress.state = this.cancelled || this.opts.signal?.aborted ? 'cancelled' : 'done';
    this.progress.currentName = '';
    this.emit(true);
    return { ...this.progress, errors: [...this.progress.errors] };
  }

  /** 返回 'done' 或 'skipped'。 */
  private async fetchOne(item: DownloadItem): Promise<'done' | 'skipped'> {
    const dest = safeJoin(this.opts.root, item.relativePath);
    await mkdir(dirname(dest), { recursive: true });

    // 已经下过且大小一致就跳过。
    if (this.opts.skipExisting !== false && item.size > 0) {
      try {
        const st = await stat(dest);
        if (st.isFile() && st.size === item.size) return 'skipped';
      } catch {
        // 文件不存在，继续下载。
      }
    }

    const partPath = `${dest}.part`;

    let lastError: unknown;
    for (let attempt = 0; attempt <= MAX_RETRIES; attempt += 1) {
      if (this.cancelled || this.opts.signal?.aborted) break;
      try {
        await this.streamTo(item, partPath);
        await rename(partPath, dest);
        return 'done';
      } catch (err) {
        lastError = err;
        await unlink(partPath).catch(() => {});
        if (this.cancelled || this.opts.signal?.aborted) break;
        // 退避一下再试，避免服务端瞬时问题直接算失败。
        if (attempt < MAX_RETRIES) {
          await new Promise((r) => setTimeout(r, 400 * (attempt + 1)));
        }
      }
    }
    throw lastError instanceof Error ? lastError : new Error(String(lastError));
  }
  private async streamTo(item: DownloadItem, partPath: string): Promise<void> {
    const cookie = this.opts.jar.getCookieHeader(item.url);
    const headers: Record<string, string> = {
      'User-Agent': DEFAULT_UA,
      'Accept-Language': 'zh-CN,zh;q=0.9',
      Accept: '*/*',
    };
    if (cookie) headers['Cookie'] = cookie;

    const res = await fetch(item.url, {
      headers,
      redirect: 'follow',
      signal: this.opts.signal,
    });
    if (!res.ok || !res.body) {
      throw new Error(`HTTP ${res.status}${res.status === 403 ? '（链接可能已过期，请刷新后重试）' : ''}`);
    }

    // 服务端给了长度就以它为准（可能和接口里的 size 不一致）。
    const len = Number(res.headers.get('content-length') ?? '0');
    if (Number.isFinite(len) && len > 0) {
      this.progress.currentTotal = len;
      // bytesTotal 用的是接口里的大小；这里只影响当前文件的显示。
    }

    const body = Readable.fromWeb(res.body as Parameters<typeof Readable.fromWeb>[0]);
    body.on('data', (chunk: Buffer) => {
      const n = chunk.length;
      this.progress.currentReceived += n;
      this.progress.bytesReceived += n;
      this.emit();
    });

    await pipeline(body, createWriteStream(partPath));
  }
}
