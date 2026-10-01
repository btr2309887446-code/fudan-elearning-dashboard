/**
 * Electron main process.
 *
 * All network work (UIS login, Canvas REST) happens here rather than in the
 * renderer: Canvas sends no CORS headers, and the session cookie must never be
 * exposed to web content. The renderer only ever sees plain JSON over IPC.
 */

import { app, BrowserWindow, dialog, ipcMain, safeStorage, shell } from 'electron';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildSnapshot } from '../core/aggregate.ts';
import { CookieJar } from '../core/cookies.ts';
import { buildDemoFileTree, buildDemoSnapshot } from '../core/demo.ts';
import { describeCanvasError, LoginError } from '../core/errors.ts';
import {
  buildFileTree,
  flattenFiles,
  planDownloadPaths,
  treeStats,
  type FileNode,
} from '../core/files.ts';
import { loadSession, makeClient, saveSession, verifySession } from '../core/session.ts';
import { normaliseSnapshot } from '../core/scoring.ts';
import {
  fallbackSummary,
  htmlToPlainText,
  summarizeAssignment,
  summaryCacheKey,
  DEFAULT_LLM,
  type LlmConfig,
} from '../core/summary.ts';
import type { CanvasProfile, Snapshot } from '../core/types.ts';
import { beginLogin, checkCaptcha, completeLogin, type LoginContext } from '../core/uis.ts';
import { DownloadManager, type DownloadItem, type DownloadProgress } from './download.ts';

interface Prefs {
  rememberUsername: boolean;
  username?: string;
  /** base64 of an OS-encrypted password blob; only written when opted in. */
  encryptedPassword?: string;
  rememberPassword: boolean;
  enrollmentState: 'active' | 'all';
  /** Hide assignments the student has not handed in yet. Display-only. */
  hideUnsubmitted: boolean;
  theme: 'light' | 'dark';
  /** 课程文件的下载根目录；未设置时用「下载/eLearning」。 */
  downloadRoot?: string;
  /** 首页各板块的显示开关；缺省视为全开。 */
  dashboardSections?: Record<string, boolean>;
  /** 首页板块的排列顺序（section key 列表）；空数组表示默认顺序。 */
  dashboardOrder?: string[];
  /** 大模型配置；未配置时作业简介降级为截取描述前 100 字。 */
  llm?: LlmConfig;
  /** 作业简介缓存，键是 summaryCacheKey()。 */
  summaryCache?: Record<string, string>;
}

interface IpcOk<T> {
  ok: true;
  data: T;
}
interface IpcErr {
  ok: false;
  error: { kind: string; message: string; detail?: string };
}
type IpcResult<T> = IpcOk<T> | IpcErr;

let mainWindow: BrowserWindow | null = null;
let loginCtx: LoginContext | null = null;
let snapshot: Snapshot | null = null;
let refreshing = false;

/** UI preview mode: synthetic data, no network, no credentials. */
const DEMO = process.env['ELEARNING_DEMO'] === '1' || process.argv.includes('--demo');

// --- paths ------------------------------------------------------------------

const userDir = () => app.getPath('userData');
const sessionPath = () => join(userDir(), 'session.json');
const snapshotPath = () => join(userDir(), 'snapshot.json');
const prefsPath = () => join(userDir(), 'prefs.json');

/** 未设置时的下载根目录：「下载」文件夹下建一个 eLearning。 */
const defaultDownloadRoot = (): string => join(app.getPath('downloads'), 'eLearning');

function ensureUserDir(): void {
  const dir = userDir();
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

function readPrefs(): Prefs {
  const defaults: Prefs = {
    rememberUsername: true,
    rememberPassword: false,
    enrollmentState: 'all',
    hideUnsubmitted: false,
    theme: 'light',
  };
  try {
    if (!existsSync(prefsPath())) return defaults;
    return { ...defaults, ...(JSON.parse(readFileSync(prefsPath(), 'utf8')) as Partial<Prefs>) };
  } catch {
    return defaults;
  }
}

function writePrefs(prefs: Prefs): void {
  ensureUserDir();
  writeFileSync(prefsPath(), JSON.stringify(prefs, null, 2), 'utf8');
}

/**
 * Read the on-disk cache defensively. A snapshot written by an older version
 * may be missing fields the current UI relies on, so it is normalised before
 * it ever reaches the renderer; anything unsalvageable is dropped.
 */
function readCachedSnapshot(): Snapshot | null {
  try {
    if (!existsSync(snapshotPath())) return null;
    const raw: unknown = JSON.parse(readFileSync(snapshotPath(), 'utf8'));
    const normalised = normaliseSnapshot(raw);
    if (!normalised) {
      console.warn('[cache] snapshot.json has an unrecognised shape; ignoring it.');
      return null;
    }
    return normalised;
  } catch (err) {
    console.warn('[cache] could not read snapshot.json:', (err as Error).message);
    return null;
  }
}

function writeCachedSnapshot(s: Snapshot): void {
  ensureUserDir();
  writeFileSync(snapshotPath(), JSON.stringify(s), 'utf8');
}

function currentJar(): CookieJar | null {
  const saved = loadSession(sessionPath());
  return saved ? saved.jar : null;
}

function fail(err: unknown): IpcErr {
  if (err instanceof LoginError) {
    return { ok: false, error: { kind: err.kind, message: err.message, detail: err.detail } };
  }
  return {
    ok: false,
    error: { kind: 'unknown', message: describeCanvasError(err) || String(err) },
  };
}

// --- snapshot ---------------------------------------------------------------

async function refreshSnapshot(force: boolean): Promise<Snapshot> {
  // 演示模式同样要落到模块变量里，否则按 id 查作业（详情页）会落空。
  if (DEMO) {
    snapshot = buildDemoSnapshot();
    return snapshot;
  }

  if (refreshing) {
    if (snapshot) return snapshot;
    throw new Error('正在刷新，请稍候。');
  }

  const jar = currentJar();
  if (!jar) throw new LoginError('session_expired', '尚未登录。');

  if (!force && snapshot) return snapshot;

  refreshing = true;
  try {
    const client = makeClient(jar);
    const profile = await verifySession(client);
    if (!profile) {
      throw new LoginError('session_expired', '登录状态已失效，请重新登录。');
    }
    const prefs = readPrefs();
    const built = await buildSnapshot(client, {
      enrollmentState: prefs.enrollmentState,
      onProgress: (done, total, label) => {
        mainWindow?.webContents.send('data:progress', { done, total, label });
      },
    });
    snapshot = built;
    writeCachedSnapshot(built);

    // Keep the refreshed cookies so the session survives as long as possible.
    saveSession(sessionPath(), jar, { username: profile.login_id, displayName: profile.name });
    return built;
  } finally {
    refreshing = false;
  }
}

// --- login ------------------------------------------------------------------

function passwordBlob(password: string): string | undefined {
  try {
    if (!safeStorage.isEncryptionAvailable()) return undefined;
    return safeStorage.encryptString(password).toString('base64');
  } catch {
    return undefined;
  }
}

function readPasswordBlob(prefs: Prefs): string | undefined {
  if (!prefs.rememberPassword || !prefs.encryptedPassword) return undefined;
  try {
    if (!safeStorage.isEncryptionAvailable()) return undefined;
    return safeStorage.decryptString(Buffer.from(prefs.encryptedPassword, 'base64'));
  } catch {
    return undefined;
  }
}

/**
 * 演示模式下的假下载：不联网、不落盘，只把进度条走一遍，
 * 用于在没有账号的环境里检查界面。
 */
async function simulateDemoDownload(
  args: { courseId: number; fileIds?: number[] },
  win: BrowserWindow | null
): Promise<IpcResult<DownloadProgress>> {
  const all = flattenFiles(buildDemoFileTree(args.courseId));
  const wanted =
    args.fileIds && args.fileIds.length > 0
      ? all.filter((n) => n.file && args.fileIds!.includes(n.file.id))
      : all;

  if (wanted.length === 0) {
    return { ok: false, error: { kind: 'empty', message: '没有选中任何文件' } };
  }

  const bytesTotal = wanted.reduce((s, n) => s + (n.size ?? 0), 0);
  const progress: DownloadProgress = {
    total: wanted.length,
    completed: 0,
    skipped: 1,
    failed: 0,
    currentName: '',
    bytesReceived: 0,
    bytesTotal,
    currentReceived: 0,
    currentTotal: 0,
    errors: [],
    state: 'running',
  };

  const STEPS = 20;
  for (let i = 0; i < wanted.length; i += 1) {
    const node = wanted[i];
    const size = node.size ?? 0;
    progress.currentName = node.name;
    progress.currentTotal = size;
    progress.currentReceived = 0;
    for (let s = 0; s < STEPS; s += 1) {
      await new Promise((r) => setTimeout(r, 55));
      const delta = size / STEPS;
      progress.currentReceived += delta;
      progress.bytesReceived += delta;
      win?.webContents.send('files:progress', { ...progress, errors: [] });
    }
    progress.completed += 1;
  }

  progress.state = 'done';
  progress.currentName = '';
  win?.webContents.send('files:progress', { ...progress, errors: [] });
  return { ok: true, data: { ...progress, errors: [] } };
}

function registerIpc(): void {  ipcMain.handle('prefs:get', (): Prefs => {
    const prefs = readPrefs();
    // Never ship the encrypted blob to the renderer.
    return { ...prefs, encryptedPassword: undefined };
  });

  ipcMain.handle('prefs:set', (_e, patch: Partial<Prefs>): Prefs => {
    const prefs = { ...readPrefs(), ...patch };
    writePrefs(prefs);
    return { ...prefs, encryptedPassword: undefined };
  });

  /** Step 1: reach the IdP and find out whether a captcha is pending. */
  ipcMain.handle('auth:prepare', async (_e, username: string): Promise<IpcResult<{ captchaRequired: boolean; captchaImage?: string }>> => {
    try {
      loginCtx = await beginLogin();
      const captcha = await checkCaptcha(loginCtx, username);
      return { ok: true, data: { captchaRequired: captcha.required, captchaImage: captcha.image } };
    } catch (err) {
      loginCtx = null;
      return fail(err);
    }
  });

  /** Re-check the captcha state after the username changed (no new lck). */
  ipcMain.handle('auth:checkCaptcha', async (_e, username: string): Promise<IpcResult<{ captchaRequired: boolean; captchaImage?: string }>> => {
    try {
      if (!loginCtx) loginCtx = await beginLogin();
      const captcha = await checkCaptcha(loginCtx, username);
      return { ok: true, data: { captchaRequired: captcha.required, captchaImage: captcha.image } };
    } catch (err) {
      return fail(err);
    }
  });

  /** Step 2: spend exactly one authentication attempt. */
  ipcMain.handle(
    'auth:submit',
    async (
      _e,
      payload: { username: string; password: string; captchaCode?: string; remember?: boolean }
    ): Promise<IpcResult<{ profile: CanvasProfile }>> => {
      try {
        const ctx = loginCtx ?? (await beginLogin());
        loginCtx = null;
        const result = await completeLogin(ctx, {
          username: payload.username,
          password: payload.password,
          captchaCode: payload.captchaCode,
        });

        const client = makeClient(result.jar);
        const profile = await verifySession(client);
        if (!profile) {
          return {
            ok: false,
            error: { kind: 'protocol', message: '登录已通过认证服务器，但 eLearning 会话无效。' },
          };
        }

        saveSession(sessionPath(), result.jar, { username: payload.username, displayName: profile.name });

        const prefs = readPrefs();
        prefs.username = payload.username;
        prefs.rememberUsername = true;
        if (payload.remember) {
          prefs.rememberPassword = true;
          const blob = passwordBlob(payload.password);
          if (blob) prefs.encryptedPassword = blob;
        } else {
          prefs.rememberPassword = false;
          prefs.encryptedPassword = undefined;
        }
        writePrefs(prefs);

        snapshot = null;
        return { ok: true, data: { profile } };
      } catch (err) {
        return fail(err);
      }
    }
  );

  ipcMain.handle('auth:status', async (): Promise<IpcResult<{ loggedIn: boolean; profile?: CanvasProfile; savedAt?: string }>> => {
    if (DEMO) {
      const demo = buildDemoSnapshot();
      return { ok: true, data: { loggedIn: true, profile: demo.profile, savedAt: demo.fetchedAt } };
    }
    const prefs = readPrefs();
    const saved = loadSession(sessionPath());
    if (!saved) {
      return { ok: true, data: { loggedIn: false } };
    }
    const profile = await verifySession(makeClient(saved.jar));
    return {
      ok: true,
      data: {
        loggedIn: profile !== null,
        profile: profile ?? undefined,
        savedAt: saved.file.savedAt,
      },
    };
  });

  ipcMain.handle('auth:remembered', (): { username?: string; password?: string } => {
    const prefs = readPrefs();
    return {
      username: prefs.rememberUsername ? prefs.username : undefined,
      password: readPasswordBlob(prefs),
    };
  });

  ipcMain.handle('auth:logout', (): IpcResult<true> => {
    try {
      const prefs = readPrefs();
      prefs.encryptedPassword = undefined;
      writePrefs(prefs);
      if (existsSync(sessionPath())) writeFileSync(sessionPath(), '{}', 'utf8');
      snapshot = null;
      return { ok: true, data: true };
    } catch (err) {
      return fail(err);
    }
  });

  ipcMain.handle('data:snapshot', async (_e, opts: { force?: boolean } = {}): Promise<IpcResult<Snapshot>> => {
    try {
      return { ok: true, data: await refreshSnapshot(opts.force === true) };
    } catch (err) {
      return fail(err);
    }
  });

  ipcMain.handle('data:cached', (): Snapshot | null => {
    // 演示模式也要把快照存进模块变量：否则渲染进程拿到了数据，
    // 主进程这边的 `snapshot` 仍是 null，任何按 id 查作业的功能
    //（比如作业详情）都会查不到东西。
    if (DEMO) {
      snapshot = buildDemoSnapshot();
      return snapshot;
    }
    if (!snapshot) snapshot = readCachedSnapshot();
    return snapshot;
  });

  /** Escape hatch used by the error screen: forget cache and session. */
  ipcMain.handle('data:clear', (): IpcResult<true> => {
    try {
      snapshot = null;
      for (const file of [snapshotPath(), sessionPath()]) {
        if (existsSync(file)) writeFileSync(file, '{}', 'utf8');
      }
      return { ok: true, data: true };
    } catch (err) {
      return fail(err);
    }
  });

  ipcMain.handle('shell:open', async (_e, url: string): Promise<void> => {
    if (/^https:\/\/[a-z0-9.-]*fudan\.edu\.cn/i.test(url)) await shell.openExternal(url);
  });

  // --- 课程文件 ------------------------------------------------------------

  /**
   * 已取回的课程文件树。
   *
   * 缓存在主进程里有两个原因：界面上反复展开收起不该反复打接口；
   * 下载时也只接受渲染进程传来的 courseId + fileIds，
   * 磁盘路径一律由主进程自己算，避免信任渲染进程给的路径。
   */
  const fileTreeCache = new Map<number, FileNode>();

  async function getCourseFileTree(courseId: number, force = false): Promise<FileNode> {
    if (DEMO) return buildDemoFileTree(courseId);
    if (!force && fileTreeCache.has(courseId)) return fileTreeCache.get(courseId)!;
    const jar = currentJar();
    if (!jar) throw new Error('尚未登录');
    const client = makeClient(jar);
    const [folders, files] = await Promise.all([
      client.getCourseFolders(courseId),
      client.getCourseFiles(courseId),
    ]);
    const tree = buildFileTree(folders, files);
    fileTreeCache.set(courseId, tree);
    return tree;
  }

  ipcMain.handle(
    'files:course',
    async (_e, args: { courseId: number; force?: boolean }): Promise<IpcResult<{ tree: FileNode; stats: { count: number; bytes: number } }>> => {
      try {
        const tree = await getCourseFileTree(args.courseId, args.force === true);
        return { ok: true, data: { tree, stats: treeStats(tree) } };
      } catch (err) {
        return fail(err);
      }
    }
  );

  ipcMain.handle('files:root', (): string => readPrefs().downloadRoot ?? defaultDownloadRoot());

  /** 侧边栏底部显示版本号，免得装了两版看起来一样分不清。 */
  ipcMain.handle('app:version', (): string => app.getVersion());

  // --- 作业详情与简介 -------------------------------------------------------

  /** 大模型配置（读）。API key 只在主进程里用，不主动回传渲染进程全文。 */
  ipcMain.handle('llm:get', (): LlmConfig => {
    const cfg = readPrefs().llm ?? DEFAULT_LLM;
    // 回传时把 key 打码，界面上只需要知道「配没配」。
    return { ...cfg, apiKey: cfg.apiKey ? '********' : '' };
  });

  ipcMain.handle('llm:set', (_e, patch: Partial<LlmConfig> & { apiKey?: string }): IpcResult<LlmConfig> => {
    try {
      const current = readPrefs().llm ?? DEFAULT_LLM;
      // 传进来的是打码串说明用户没改 key，保留原来的。
      const nextKey =
        patch.apiKey === undefined || patch.apiKey === '********'
          ? current.apiKey
          : patch.apiKey.trim();
      const next: LlmConfig = {
        baseUrl: (patch.baseUrl ?? current.baseUrl).trim().replace(/\/+$/, ''),
        model: (patch.model ?? current.model).trim(),
        enabled: patch.enabled ?? current.enabled,
        apiKey: nextKey,
      };
      writePrefs({ ...readPrefs(), llm: next });
      return { ok: true, data: { ...next, apiKey: next.apiKey ? '********' : '' } };
    } catch (err) {
      return fail(err);
    }
  });

  /**
   * 取作业详情并生成简介。
   *
   * 完整描述按需拉取（列表里只存了摘录），简介会缓存——
   * 同一份描述只花一次大模型调用。
   */
  ipcMain.handle(
    'assignment:detail',
    async (
      _e,
      args: { courseId: number; assignmentId: number }
    ): Promise<
      IpcResult<{
        description: string;
        summary: string;
        summarySource: 'llm' | 'fallback';
        summaryError?: string;
        cached: boolean;
      }>
    > => {
      try {
        // 演示模式：没有会话可拉接口，直接用快照里存的摘录。
        if (DEMO) {
          const row = snapshot?.assignments.find((a) => a.id === args.assignmentId);
          const desc = row?.descriptionExcerpt ?? '';
          return {
            ok: true,
            data: {
              description: desc,
              summary: fallbackSummary(desc),
              summarySource: 'fallback' as const,
              cached: false,
            },
          };
        }

        const jar = currentJar();
        if (!jar) throw new Error('尚未登录');
        const client = makeClient(jar);
        const assignment = await client.getAssignment(args.courseId, args.assignmentId);
        const description = assignment.description ?? '';

        const prefs = readPrefs();
        const cfg = prefs.llm ?? DEFAULT_LLM;
        const key = summaryCacheKey(args.assignmentId, description);
        const cache = { ...(prefs.summaryCache ?? {}) };

        if (cache[key]) {
          return {
            ok: true,
            data: {
              description,
              summary: cache[key],
              summarySource: cfg.enabled ? 'llm' : 'fallback',
              cached: true,
            },
          };
        }

        const result = await summarizeAssignment(assignment.name, description, cfg);
        if (result.summary) {
          cache[key] = result.summary;
          // 缓存别无限长：按插入顺序裁掉最早的。
          const keys = Object.keys(cache);
          if (keys.length > 400) for (const k of keys.slice(0, keys.length - 400)) delete cache[k];
          writePrefs({ ...prefs, summaryCache: cache });
        }

        return {
          ok: true,
          data: {
            description,
            summary: result.summary,
            summarySource: result.source,
            summaryError: result.error,
            cached: false,
          },
        };
      } catch (err) {
        return fail(err);
      }
    }
  );

  /** 只算简介，不重新拉描述——详情页已经有描述时用。 */
  ipcMain.handle(
    'assignment:summarise',
    async (
      _e,
      args: { assignmentId: number; name: string; description: string }
    ): Promise<IpcResult<{ summary: string; summarySource: 'llm' | 'fallback'; summaryError?: string }>> => {
      try {
        const prefs = readPrefs();
        const cfg = prefs.llm ?? DEFAULT_LLM;
        const result = await summarizeAssignment(args.name, args.description, cfg);
        if (result.summary) {
          const cache = { ...(prefs.summaryCache ?? {}) };
          cache[summaryCacheKey(args.assignmentId, args.description)] = result.summary;
          writePrefs({ ...prefs, summaryCache: cache });
        }
        return {
          ok: true,
          data: { summary: result.summary, summarySource: result.source, summaryError: result.error },
        };
      } catch (err) {
        return fail(err);
      }
    }
  );

  ipcMain.handle(
    'files:pickRoot',
    async (): Promise<IpcResult<string>> => {
      try {
        const res = await dialog.showOpenDialog({
          title: '选择课程文件的下载位置',
          defaultPath: readPrefs().downloadRoot ?? defaultDownloadRoot(),
          properties: ['openDirectory', 'createDirectory'],
        });
        if (res.canceled || res.filePaths.length === 0) return { ok: false, error: { kind: 'cancelled', message: '已取消' } };
        const picked = res.filePaths[0];
        writePrefs({ ...readPrefs(), downloadRoot: picked });
        return { ok: true, data: picked };
      } catch (err) {
        return fail(err);
      }
    }
  );

  let activeDownload: DownloadManager | null = null;

  ipcMain.handle('files:cancel', (): IpcResult<true> => {
    activeDownload?.cancel();
    activeDownload = null;
    return { ok: true, data: true };
  });

  ipcMain.handle(
    'files:download',
    async (
      _e,
      args: { courseId: number; fileIds?: number[] }
    ): Promise<IpcResult<DownloadProgress>> => {
      try {
        if (activeDownload) return { ok: false, error: { kind: 'busy', message: '已有下载任务在进行中' } };

        // 演示模式：不联网、不落盘，只把进度条演一遍。
        if (DEMO) return await simulateDemoDownload(args, mainWindow);

        const jar = currentJar();
        if (!jar) throw new Error('尚未登录');

        const course = snapshot?.courses.find((c) => c.id === args.courseId);
        const termName = course?.termName || '未分学期';
        const courseName = course?.displayName || course?.name || `课程 ${args.courseId}`;

        const tree = await getCourseFileTree(args.courseId);
        const all = flattenFiles(tree);
        const wanted =
          args.fileIds && args.fileIds.length > 0
            ? all.filter((n) => n.file && args.fileIds!.includes(n.file.id))
            : all;

        if (wanted.length === 0) {
          return { ok: false, error: { kind: 'empty', message: '这门课没有可下载的文件' } };
        }

        // 由主进程自己算磁盘路径，渲染进程只提供 fileId。
        const plan = planDownloadPaths(
          termName,
          courseName,
          wanted.map((n) => {
            const slash = n.path.lastIndexOf('/');
            return {
              folderPath: slash < 0 ? '' : n.path.slice(0, slash),
              fileName: n.name,
              file: n.file!,
            };
          })
        );

        const items: DownloadItem[] = plan.map((p, i) => ({
          fileId: p.file.id,
          url: p.file.url,
          relativePath: p.relativePath,
          size: p.file.size,
          name: wanted[i].name,
        }));

        const root = readPrefs().downloadRoot ?? defaultDownloadRoot();
        mkdirSync(root, { recursive: true });

        // 取消上一轮可能仍在的监听（正常流程里上一轮已结束）。
        mainWindow?.webContents.send('files:progress', {
          total: items.length,
          completed: 0,
          skipped: 0,
          failed: 0,
          currentName: '',
          bytesReceived: 0,
          bytesTotal: items.reduce((s, i) => s + (i.size > 0 ? i.size : 0), 0),
          currentReceived: 0,
          currentTotal: 0,
          errors: [],
          state: 'running',
        } satisfies DownloadProgress);

        const mgr = new DownloadManager({
          jar,
          root,
          onProgress: (p) => mainWindow?.webContents.send('files:progress', p),
        });
        activeDownload = mgr;
        const result = await mgr.run(items);
        activeDownload = null;

        // 全部成功且无跳过时，顺便把目录打开给用户看一眼。
        if (result.failed === 0) {
          const firstSlash = items[0].relativePath.indexOf('/');
          const termDir = join(root, firstSlash > 0 ? items[0].relativePath.slice(0, firstSlash) : '');
          void shell.openPath(termDir);
        }
        return { ok: true, data: result };
      } catch (err) {
        activeDownload = null;
        return fail(err);
      }
    }
  );

  ipcMain.handle('files:reveal', async (_e, relativePath: string): Promise<void> => {
    try {
      const root = readPrefs().downloadRoot ?? defaultDownloadRoot();
      shell.showItemInFolder(join(root, relativePath));
    } catch {
      // 路径无效时静默忽略：这只是个便利功能。
    }
  });
}

// --- window -----------------------------------------------------------------

/**
 * Capture the window, working around a stale compositor frame.
 *
 * When the window is not focused Chromium throttles painting, so `capturePage`
 * can hand back the previous frame - a theme switch would then be captured as
 * the old theme. Forcing a repaint and discarding one capture fixes it.
 */
async function captureFresh(win: BrowserWindow): Promise<Electron.NativeImage> {
  // `webContents.invalidate()` was removed in newer Electron; call it only when
  // present, otherwise a missing method would abort the whole capture.
  const wc = win.webContents as unknown as { invalidate?: () => void };
  try {
    if (typeof wc.invalidate === 'function') wc.invalidate();
  } catch {
    /* not available - the retry below still handles a stale frame */
  }
  await new Promise((r) => setTimeout(r, 350));
  await win.webContents.capturePage();
  await new Promise((r) => setTimeout(r, 250));
  return win.webContents.capturePage();
}

function createWindow(): void {
  // 截图时可以把窗口开高一点，让整页无需滚动——未聚焦的窗口
  // capturePage 会返回滚动前的旧帧，不滚动就没有这个问题。
  const smokeH = Number(process.env['ELEARNING_SMOKE_HEIGHT'] ?? 0);
  const smokeW = Number(process.env['ELEARNING_SMOKE_WIDTH'] ?? 0);

  mainWindow = new BrowserWindow({
    width: smokeW > 0 ? smokeW : 1320,
    height: smokeH > 0 ? smokeH : 880,
    minWidth: 1000,
    minHeight: 660,
    show: false,
    autoHideMenuBar: true,
    backgroundColor: '#0d1220',
    title: '复旦大学 eLearning 学习看板',
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      sandbox: false,
      contextIsolation: true,
      nodeIntegration: false,
      // Keep rendering while the window is in the background: without this the
      // UI can look frozen after a refresh until the user focuses it.
      backgroundThrottling: false,
    },
  });

  mainWindow.on('ready-to-show', () => mainWindow?.show());

  // Surface renderer-side problems in the terminal while developing.
  if (!app.isPackaged) {
    mainWindow.webContents.on('console-message', (_e, level, message, line, source) => {
      console.log(`[renderer:${level}] ${message}  (${source}:${line})`);
    });
  }
  mainWindow.webContents.on('did-fail-load', (_e, code, desc, url) => {
    console.error(`[renderer] failed to load ${url}: ${code} ${desc}`);
  });
  mainWindow.webContents.on('render-process-gone', (_e, details) => {
    console.error(`[renderer] process gone: ${details.reason}`);
  });

  // Smoke mode: screenshot the first screen and exit, so the UI can be checked
  // without a human at the keyboard.
  if (process.env['ELEARNING_SMOKE']) {
    mainWindow.webContents.once('did-finish-load', () => {
      const delay = Number(process.env['ELEARNING_SMOKE_DELAY'] ?? 5000);
      setTimeout(() => {
        void (async () => {
          try {
            // Optionally drive the UI first, so any screen can be captured.
            const scriptFile = process.env['ELEARNING_SMOKE_SCRIPT_FILE'];
            const script = scriptFile
              ? readFileSync(scriptFile, 'utf8')
              : process.env['ELEARNING_SMOKE_SCRIPT'];
            if (script) {
              const view = JSON.stringify(process.env['ELEARNING_SMOKE_VIEW'] ?? 'dashboard');
              try {
                const result = await mainWindow!.webContents.executeJavaScript(
                  `const SMOKE_VIEW = ${view};\n${script}`
                );
                console.log('[smoke] driver result:', result);
              } catch (err) {
                // A broken driver must not cost us the screenshot.
                console.error('[smoke] driver threw:', (err as Error).message);
              }
              await new Promise((r) => setTimeout(r, Number(process.env['ELEARNING_SMOKE_SETTLE'] ?? 2500)));
            }
            const image = await captureFresh(mainWindow!);
            const out = join(process.cwd(), process.env['ELEARNING_SMOKE'] as string);
            writeFileSync(out, image.toPNG());
            console.log(`[smoke] screenshot written to ${out}`);
          } catch (err) {
            console.error('[smoke] capture failed:', err);
          } finally {
            app.exit(0);
          }
        })();
      }, delay);
    });
  }

  // Never let the app navigate away from its own UI.
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https:\/\//i.test(url)) void shell.openExternal(url);
    return { action: 'deny' };
  });

  const devUrl = process.env['ELECTRON_RENDERER_URL'];
  if (devUrl) {
    void mainWindow.loadURL(devUrl);
  } else {
    void mainWindow.loadFile(join(__dirname, '../renderer/index.html'));
  }
}

app.whenReady().then(() => {
  ensureUserDir();
  registerIpc();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
