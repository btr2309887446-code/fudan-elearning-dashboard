/**
 * Electron main process.
 *
 * All network work (UIS login, Canvas REST) happens here rather than in the
 * renderer: Canvas sends no CORS headers, and the session cookie must never be
 * exposed to web content. The renderer only ever sees plain JSON over IPC.
 */

import {
  app,
  BrowserWindow,
  dialog,
  ipcMain,
  safeStorage,
  shell,
  Tray,
  Menu,
  Notification,
  nativeImage,
  powerMonitor,
} from "electron";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve, relative, isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";
import { validateIpc, safeExternalUrl } from "./ipc-security.ts";
import { CredentialStore, publicPreferences, preferencePatch } from "./credentials.ts";
import { LectureService } from "./lectures/service.ts";
import { parseLectureKey, type CourseIntroduction, type LectureConnectInput, type LectureRef } from "../core/lectures.ts";
import { WorkspaceStore, atomicJson } from "./workspace-store.ts";
import {
  dueReminders,
  emptyWorkspace,
  unifyTasks,
  type WorkspaceCommand,
} from "../core/workspace.ts";
import { buildSnapshot } from "../core/aggregate.ts";
import { CookieJar } from "../core/cookies.ts";
import { buildDemoFileTree, buildDemoSnapshot } from "../core/demo.ts";
import { describeCanvasError, LoginError } from "../core/errors.ts";
import {
  buildFileTree,
  flattenFiles,
  planDownloadPaths,
  treeStats,
  type FileNode,
} from "../core/files.ts";
import {
  makeClient,
  verifySession,
} from "../core/session.ts";
import { normaliseSnapshot } from "../core/scoring.ts";
import {
  fallbackSummary,
  htmlToPlainText,
  summarizeAssignment,
  summaryCacheKey,
  DEFAULT_LLM,
  type LlmConfig,
} from "../core/summary.ts";
import type { CanvasProfile, Snapshot } from "../core/types.ts";
import {
  beginLogin,
  checkCaptcha,
  completeLogin,
  type LoginContext,
} from "../core/uis.ts";
import {
  DownloadManager,
  type DownloadItem,
  type DownloadProgress,
} from "./download.ts";

interface Prefs {
  rememberUsername: boolean;
  username?: string;
  /** base64 of an OS-encrypted password blob; only written when opted in. */
  encryptedPassword?: string;
  rememberPassword: boolean;
  enrollmentState: "active" | "all";
  /** Hide assignments the student has not handed in yet. Display-only. */
  hideUnsubmitted: boolean;
  theme: "light" | "dark";
  followSystem?: boolean;
  syncMinutes?: 0 | 15 | 30 | 60;
  closeToTray?: boolean;
  taskNotifications?: boolean;
  changeNotifications?: boolean;
  /** 课程文件的下载根目录；未设置时用「下载/eLearning」。 */
  downloadRoot?: string;
  /** 首页各板块的显示开关；缺省视为全开。 */
  dashboardSections?: Record<string, boolean>;
  /** 首页板块的排列顺序（section key 列表）；空数组表示默认顺序。 */
  dashboardOrder?: string[];
  /** 手动标记为「无需提交」的作业键（`courseId:assignmentId`）。只影响显示。 */
  ignoredAssignments?: string[];
  /**
   * 刷新范围：`current` 只请求当前及未来学期（默认），`all` 全部重拉。
   *
   * 已结束学期的成绩和作业不会再变，每次刷新都拉一遍纯属浪费。
   */
  refreshScope?: "current" | "all";
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
const DEMO =
  process.env["ELEARNING_DEMO"] === "1" || process.argv.includes("--demo");

// --- paths ------------------------------------------------------------------

if (DEMO)
  app.setPath(
    "userData",
    process.env["ELEARNING_DEMO_DIR"] ||
      join(app.getPath("temp"), "fudan-elearning-workspace-demo"),
  );
const userDir = () => app.getPath("userData");
const sessionPath = () => join(userDir(), "session.json");
const snapshotPath = () => join(userDir(), "snapshot.json");
const prefsPath = () => join(userDir(), "prefs.json");
let credentialStore: CredentialStore | undefined;
function credentials() {
  return credentialStore ??= new CredentialStore(join(userDir(), "credentials.json"), {
    available: () => safeStorage.isEncryptionAvailable(),
    encrypt: value => safeStorage.encryptString(value).toString("base64"),
    decrypt: value => safeStorage.decryptString(Buffer.from(value, "base64")),
  });
}
const loadSession = (path: string) => credentials().loadSession(path);
const saveSession = (path: string, jar: CookieJar, extra: { username?: string; displayName?: string }) => credentials().saveSession(path, jar, extra);
let cachedPrefs: Prefs | undefined;
function publicPrefs(prefs: Prefs) {
  return { ...publicPreferences(prefs), storageWarning: credentials().warning } as import("../preload/index.d").Prefs;
}

/** 未设置时的下载根目录：「下载」文件夹下建一个 eLearning。 */
const defaultDownloadRoot = (): string =>
  join(app.getPath("downloads"), "eLearning");

function ensureUserDir(): void {
  const dir = userDir();
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

function readPrefs(): Prefs {
  if (cachedPrefs) return cachedPrefs;
  const defaults: Prefs = {
    rememberUsername: true,
    rememberPassword: false,
    enrollmentState: "all",
    hideUnsubmitted: false,
    theme: "light",
  };
  try {
    const result: Prefs = {
      ...defaults,
      ...(existsSync(prefsPath()) ? JSON.parse(readFileSync(prefsPath(), "utf8")) as Partial<Prefs> : {}),
    };
    let legacyBackup: Prefs | undefined;
    try { if (existsSync(`${prefsPath()}.bak`)) legacyBackup = JSON.parse(readFileSync(`${prefsPath()}.bak`, "utf8")); } catch { /* Preserve malformed backups. */ }
    const legacy = result.llm?.apiKey || legacyBackup?.llm?.apiKey;
    if (!result.llm && legacyBackup?.llm && legacy) result.llm = { ...legacyBackup.llm };
    if (legacy) {
      try { credentials().import("llm", legacy); }
      catch { credentials().warning = "AI 密钥迁移未完成，原数据已保留，下次启动会重试。"; }
    }
    if (result.llm) result.llm = { ...result.llm, apiKey: credentials().get("llm") ?? legacy ?? "" };
    cachedPrefs = result;
    if (legacy && credentials().persisted("llm")) {
      try { writePrefs(result); } catch { credentials().warning = "密钥已加密，旧设置清理未完成，下次启动会重试。"; }
    }
    return result;
  } catch {
    return defaults;
  }
}

function writePrefs(prefs: Prefs): void {
  ensureUserDir();
  const key = prefs.llm?.apiKey || undefined;
  if (credentials().get("llm") !== key || !credentials().persisted("llm")) credentials().set("llm", key);
  const clean = { ...prefs, llm: prefs.llm ? { ...prefs.llm, apiKey: "" } : undefined };
  // Preserve a legacy plaintext file only while migration cannot be committed.
  const oldHasKey = existsSync(prefsPath()) && !!JSON.parse(readFileSync(prefsPath(), "utf8")).llm?.apiKey;
  const backup = `${prefsPath()}.bak`;
  const backupHasKey = existsSync(backup) && !!JSON.parse(readFileSync(backup, "utf8")).llm?.apiKey;
  if ((oldHasKey || backupHasKey) && key && !credentials().persisted("llm")) { cachedPrefs = prefs; return; }
  atomicJson(prefsPath(), clean, false);
  if (existsSync(backup)) {
    const old = JSON.parse(readFileSync(backup, "utf8"));
    if (old.llm?.apiKey) { old.llm.apiKey = ""; atomicJson(backup, old, false); }
  }
  cachedPrefs = prefs;
}

/**
 * Read the on-disk cache defensively. A snapshot written by an older version
 * may be missing fields the current UI relies on, so it is normalised before
 * it ever reaches the renderer; anything unsalvageable is dropped.
 */
function readCachedSnapshot(): Snapshot | null {
  try {
    if (!existsSync(snapshotPath())) return null;
    const raw: unknown = JSON.parse(readFileSync(snapshotPath(), "utf8"));
    const normalised = normaliseSnapshot(raw);
    if (!normalised) {
      console.warn(
        "[cache] snapshot.json has an unrecognised shape; ignoring it.",
      );
      return null;
    }
    return normalised;
  } catch (err) {
    console.warn(
      "[cache] could not read snapshot.json:",
      (err as Error).message,
    );
    return null;
  }
}

function writeCachedSnapshot(s: Snapshot): void {
  ensureUserDir();
  atomicJson(snapshotPath(), s);
}

function currentJar(): CookieJar | null {
  const saved = loadSession(sessionPath());
  return saved ? saved.jar : null;
}

function fail(err: unknown): IpcErr {
  if (err instanceof LoginError) {
    return {
      ok: false,
      error: { kind: err.kind, message: err.message, detail: err.detail },
    };
  }
  return {
    ok: false,
    error: {
      kind: "unknown",
      message: describeCanvasError(err) || String(err),
    },
  };
}

// --- snapshot ---------------------------------------------------------------

let pendingRefresh: Promise<Snapshot> | null = null;
let pendingRefreshEpoch = -1;
let accountEpoch = 0;
let syncPaused = false;
let lectureService: LectureService | undefined;
let pendingSync: Promise<Snapshot> | null = null;
let pendingSyncEpoch = -1;
let notificationBatchDepth = 0;
function lectures(): LectureService {
  return lectureService ??= new LectureService({
    root: join(userDir(), "classroom"),
    workerPath: join(__dirname, "lecture-worker.js"),
    wasmPath: require.resolve("sql.js/dist/sql-wasm.wasm"),
    protect: (value) => {
      if (!safeStorage.isEncryptionAvailable()) throw new Error("Windows 安全存储不可用，请取消在本机记住后重试");
      return safeStorage.encryptString(value).toString("base64");
    },
    unprotect: value => safeStorage.decryptString(Buffer.from(value, "base64")),
    isCurrent: id => snapshot?.profile.id === id,
    onUpdated: () => mainWindow?.webContents.send("lectures:updated"),
    onResources: (id, resources) => {
      if (snapshot?.profile.id !== id) throw new Error("账号已切换");
      const store = workspaceStore();
      const previous = new Set(store.read(id).changes.map(c => c.id));
      const data = store.ingest(id, resources, new Date().toISOString());
      mainWindow?.webContents.send("workspace:updated");
      const changes = data.changes.filter(c => !previous.has(c.id));
      if (!notificationBatchDepth && readPrefs().changeNotifications && changes.length)
        notify(`${changes.length} 条课堂笔记更新`, "打开变化中心查看详情", id, { page: "changes", batch: changes[0].batch });
    },
    demoSnapshot: DEMO ? () => snapshot : undefined,
  });
}
/** Canvas authentication and iCourse unlocking are independent resources. */
async function synchronize(force: boolean, full = false, includeCanvas = true): Promise<Snapshot> {
  if (pendingSync && pendingSyncEpoch === accountEpoch) {
    await pendingSync;
    if (full) return synchronize(force, full, includeCanvas);
    if (!snapshot) throw new Error("请先加载账号");
    return snapshot;
  }
  const epoch = accountEpoch;
  const id = snapshot?.profile.id;
  const previous = new Set(id ? workspaceStore().read(id).changes.map(c => c.id) : []);
  const work = async () => {
    notificationBatchDepth++;
    try {
      const [canvas, notes] = await Promise.allSettled([
        includeCanvas ? refreshSnapshot(force, full) : Promise.resolve(snapshot),
        (async () => {
          if (!id) return;
          const state = await lectures().state(id);
          if (state.configured && !state.locked) return lectures().sync(id);
        })(),
      ]);
      if (epoch !== accountEpoch) throw new Error("账号已切换，请重新同步");
      if (id && readPrefs().changeNotifications) {
        const changes = workspaceStore().read(id).changes.filter(c => !previous.has(c.id));
        if (changes.length) notify(`${changes.length} 条课程更新`, "打开变化中心查看详情", id, { page: "changes" });
      }
      if (canvas.status === "rejected") throw canvas.reason;
      if (!canvas.value) throw new Error("请先加载账号");
      const issue = notes.status === "rejected" ? String(notes.reason) : notes.value?.error;
      return issue ? { ...canvas.value, warnings: [...canvas.value.warnings, `课堂笔记：${issue}`] } : canvas.value;
    } finally { notificationBatchDepth--; }
  };
  const operation = work();
  pendingSync = operation;
  pendingSyncEpoch = epoch;
  try { return await operation; } finally { if (pendingSync === operation) pendingSync = null; }
}
function workspaceStore() {
  return new WorkspaceStore(join(userDir(), "accounts"));
}
function activeAccount(): number {
  if (!snapshot) throw new Error("请先加载账号");
  return snapshot.profile.id;
}
async function refreshSnapshot(
  force: boolean,
  full = false,
): Promise<Snapshot> {
  if (pendingRefresh && pendingRefreshEpoch === accountEpoch) {
    await pendingRefresh;
    if (full) return refreshSnapshot(force, full);
    return snapshot!;
  }
  const operation = performRefresh(force, full);
  pendingRefresh = operation;
  pendingRefreshEpoch = accountEpoch;
  try {
    return await operation;
  } finally {
    if (pendingRefresh === operation) pendingRefresh = null;
  }
}
async function performRefresh(
  force: boolean,
  full: boolean,
): Promise<Snapshot> {
  const epoch = accountEpoch;
  // 演示模式同样要落到模块变量里，否则按 id 查作业（详情页）会落空。
  if (DEMO) {
    snapshot = buildDemoSnapshot();
    return snapshot;
  }

  const jar = currentJar();
  if (!jar) throw new LoginError("session_expired", "尚未登录。");

  if (!force && snapshot) return snapshot;

  refreshing = true;
  try {
    const client = makeClient(jar);
    const profile = await verifySession(client);
    if (!profile) {
      syncPaused = true;
      throw new LoginError("session_expired", "登录状态已失效，请重新登录。");
    }
    if (snapshot && snapshot.profile.id !== profile.id) {
      syncPaused = true;
      throw new LoginError("session_expired", "学校会话与当前账号不一致，请重新登录。");
    }
    const prefs = readPrefs();
    const built = await buildSnapshot(client, {
      enrollmentState: prefs.enrollmentState,
      // 已结束学期的课不会再变，沿用上次的数据，省下每门课两个请求。
      previous: snapshot ?? readCachedSnapshot(),
      full,
      trackResources: true,
      onProgress: (done, total, label) => {
        mainWindow?.webContents.send("data:progress", { done, total, label });
      },
    });
    if (epoch !== accountEpoch) throw new Error("账号已切换，请重新同步");
    writeCachedSnapshot(built);
    snapshot = built;
    const store = workspaceStore();
    const previousIds = new Set(
      store.read(profile.id).changes.map((c) => c.id),
    );
    const workspace = store.ingest(
      profile.id,
      built.resources ?? [],
      built.fetchedAt,
    );
    const changes = workspace.changes.filter((c) => !previousIds.has(c.id));
    mainWindow?.webContents.send("workspace:updated");
    if (!notificationBatchDepth && prefs.changeNotifications && changes.length)
      notify(
        `${changes.length} 条课程更新`,
        "打开变化中心查看详情",
        profile.id,
        { page: "changes", batch: changes[0].batch },
      );
    syncPaused = false;

    // Keep the refreshed cookies so the session survives as long as possible.
    saveSession(sessionPath(), jar, {
      username: profile.login_id,
      displayName: profile.name,
    });
    return built;
  } finally {
    refreshing = false;
  }
}

// --- login ------------------------------------------------------------------

function passwordBlob(password: string): string | undefined {
  try {
    if (!safeStorage.isEncryptionAvailable()) return undefined;
    return safeStorage.encryptString(password).toString("base64");
  } catch {
    return undefined;
  }
}

function readPasswordBlob(prefs: Prefs): string | undefined {
  if (!prefs.rememberPassword || !prefs.encryptedPassword) return undefined;
  try {
    if (!safeStorage.isEncryptionAvailable()) return undefined;
    return safeStorage.decryptString(
      Buffer.from(prefs.encryptedPassword, "base64"),
    );
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
  win: BrowserWindow | null,
): Promise<IpcResult<DownloadProgress>> {
  const all = flattenFiles(buildDemoFileTree(args.courseId));
  const wanted =
    args.fileIds && args.fileIds.length > 0
      ? all.filter((n) => n.file && args.fileIds!.includes(n.file.id))
      : all;

  if (wanted.length === 0) {
    return { ok: false, error: { kind: "empty", message: "没有选中任何文件" } };
  }

  const bytesTotal = wanted.reduce((s, n) => s + (n.size ?? 0), 0);
  const progress: DownloadProgress = {
    total: wanted.length,
    completed: 0,
    skipped: 1,
    failed: 0,
    currentName: "",
    bytesReceived: 0,
    bytesTotal,
    currentReceived: 0,
    currentTotal: 0,
    errors: [],
    state: "running",
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
      win?.webContents.send("files:progress", { ...progress, errors: [] });
    }
    progress.completed += 1;
  }

  progress.state = "done";
  progress.currentName = "";
  win?.webContents.send("files:progress", { ...progress, errors: [] });
  return { ok: true, data: { ...progress, errors: [] } };
}

const handle: typeof ipcMain.handle = (channel, listener) => ipcMain.handle(channel, (event, ...args) => {
  if (!mainWindow || event.sender !== mainWindow.webContents || event.senderFrame !== mainWindow.webContents.mainFrame) throw Error("请求来源无效");
  const actual = new URL(event.senderFrame.url);
  const expected = new URL(process.env["ELECTRON_RENDERER_URL"] || pathToFileURL(join(__dirname, "../renderer/index.html")).href);
  if (actual.protocol !== expected.protocol || actual.origin !== expected.origin || actual.pathname !== expected.pathname) throw Error("请求页面无效");
  validateIpc(channel, args);
  return listener(event, ...args);
});

function registerIpc(): void {
  const assertAccount = (id: number) => {
    if (!Number.isSafeInteger(id) || activeAccount() !== id) throw new Error("账号已切换，请重新打开");
  };
  const assertCourse = (id: number) => {
    if (!Number.isSafeInteger(id) || !snapshot?.courses.some(c => c.id === id)) throw new Error("当前账号无此课程");
  };
  const lectureHandler = (channel: string, action: (id: number, ...args: any[]) => Promise<unknown>) => {
    handle(channel, async (_e, id: number, ...args: any[]) => {
      try {
        assertAccount(id);
        const epoch = accountEpoch;
        const data = await action(id, ...args);
        if (epoch !== accountEpoch) throw new Error("账号已切换");
        assertAccount(id);
        return { ok: true, data };
      } catch (e) { return fail(e); }
    });
  };
  lectureHandler("lectures:state", id => lectures().state(id));
  lectureHandler("lectures:connect", (id, input: LectureConnectInput) => lectures().connect(id, input));
  lectureHandler("lectures:disconnect", id => lectures().disconnect(id));
  lectureHandler("lectures:sync", id => lectures().sync(id));
  lectureHandler("lectures:bind", (id, external: string, course: number | null) => {
    if (course !== null) assertCourse(course);
    return lectures().bind(id, external, course);
  });
  lectureHandler("lectures:list", (id, course: number, query: string, offset: number) => {
    assertCourse(course);
    return lectures().list(id, course, query, offset);
  });
  const assertRef = (ref: LectureRef) => {
    if (!ref || !parseLectureKey(JSON.stringify([ref.sourceId, ref.icourseCourseId, ref.lectureId]))) throw new Error("课次地址无效");
  };
  lectureHandler("lectures:detail", (id, ref: LectureRef) => { assertRef(ref); return lectures().detail(id, ref); });
  lectureHandler("lectures:read", (id, ref: LectureRef) => { assertRef(ref); return lectures().read(id, ref); });
  lectureHandler("course:introduction", async (id, courseId: number, force: boolean) => {
    assertCourse(courseId);
    const epoch = accountEpoch;
    const path = join(userDir(), "accounts", `introduction-${id}-${courseId}.json`);
    let cached: CourseIntroduction | undefined;
    if (existsSync(path)) {
      try {
        const file = JSON.parse(readFileSync(path, "utf8"));
        if (file.version === 1 && file.account === id && file.data?.courseId === courseId) cached = file.data;
      } catch { /* Keep the original file if it is damaged. */ }
    }
    if (DEMO) return { courseId, teachers: ["示例教师"], description: "本课程结合理论推导与课堂讨论，学习核心概念及其应用。每周安排阅读与练习，具体考核以教师发布的课程大纲为准。\n\n这是演示课程简介，所有内容均为虚构。", fetchedAt: new Date().toISOString() } satisfies CourseIntroduction;
    if (cached && !force && Date.now() - Date.parse(cached.fetchedAt) < 86400000) return { ...cached, cached: true };
    try {
      const jar = currentJar();
      if (!jar) throw new Error("登录已失效，请重新登录后刷新课程简介");
      const data = await makeClient(jar).getCourseIntroduction(courseId);
      assertAccount(id);
      if (epoch !== accountEpoch) throw new Error("账号已切换");
      mkdirSync(join(userDir(), "accounts"), { recursive: true });
      atomicJson(path, { version: 1, account: id, data });
      return data;
    } catch (e) {
      if (epoch !== accountEpoch) throw e;
      if (cached) return { ...cached, cached: true, warning: `简介未更新：${describeCanvasError(e)}` };
      throw e;
    }
  });
  handle("workspace:get", (_e, account: number) => {
    try {
      if (activeAccount() !== account) throw new Error("账号已切换");
      return { ok: true, data: workspaceStore().read(account) };
    } catch (e) {
      return fail(e);
    }
  });
  handle(
    "workspace:mutate",
    async (_e, account: number, command: WorkspaceCommand) => {
      try {
        if (activeAccount() !== account) throw new Error("账号已切换");
        const epoch = accountEpoch;
        if (command.type === "save" && command.draft.lectureSource && !command.seriesId) {
          const state = await lectures().state(account);
          const ref = command.draft.lectureSource;
          if (epoch !== accountEpoch || activeAccount() !== account) throw new Error("账号已切换");
          if (!snapshot?.courses.some(c => c.id === command.draft.courseId) || !state.configured || state.sourceId !== ref.sourceId ||
              !state.bindings.some(b => b.icourseCourseId === ref.icourseCourseId && b.canvasCourseId === command.draft.courseId))
            throw new Error("课程关联已调整，请重新从对应笔记创建任务");
        }
        if (command.type === "deadline" || command.type === "ignore") {
          const ids = command.type === "deadline" ? [command.id] : command.ids;
          if (
            ids.some(
              (id) =>
                !snapshot!.assignments.some(
                  (a) => `${a.courseId}:${a.id}` === id,
                ),
            )
          )
            throw new Error("作业不存在");
        }
        return { ok: true, data: workspaceStore().mutate(account, command) };
      } catch (e) {
        return fail(e);
      }
    },
  );
  handle("prefs:get", () => publicPrefs(readPrefs()));

  handle("prefs:set", (_e, patch: Partial<Prefs>) => {
    if (
      patch.syncMinutes !== undefined &&
      ![0, 15, 30, 60].includes(patch.syncMinutes)
    )
      throw new Error("同步间隔无效");
    const prefs = { ...readPrefs(), ...preferencePatch(patch) };
    if (prefs.rememberPassword === false) prefs.encryptedPassword = undefined;
    writePrefs(prefs);
    configureLifecycle();
    return publicPrefs(prefs);
  });

  /** Step 1: reach the IdP and find out whether a captcha is pending. */
  handle(
    "auth:prepare",
    async (
      _e,
      username: string,
    ): Promise<
      IpcResult<{ captchaRequired: boolean; captchaImage?: string }>
    > => {
      try {
        loginCtx = await beginLogin();
        const captcha = await checkCaptcha(loginCtx, username);
        return {
          ok: true,
          data: {
            captchaRequired: captcha.required,
            captchaImage: captcha.image,
          },
        };
      } catch (err) {
        loginCtx = null;
        return fail(err);
      }
    },
  );

  /** Re-check the captcha state after the username changed (no new lck). */
  handle(
    "auth:checkCaptcha",
    async (
      _e,
      username: string,
    ): Promise<
      IpcResult<{ captchaRequired: boolean; captchaImage?: string }>
    > => {
      try {
        if (!loginCtx) loginCtx = await beginLogin();
        const captcha = await checkCaptcha(loginCtx, username);
        return {
          ok: true,
          data: {
            captchaRequired: captcha.required,
            captchaImage: captcha.image,
          },
        };
      } catch (err) {
        return fail(err);
      }
    },
  );

  /** Step 2: spend exactly one authentication attempt. */
  handle(
    "auth:submit",
    async (
      _e,
      payload: {
        username: string;
        password: string;
        captchaCode?: string;
        remember?: boolean;
        useRememberedPassword?: boolean;
      },
    ): Promise<IpcResult<{ profile: CanvasProfile }>> => {
      try {
        const remembered = readPrefs();
        const password = payload.password || (payload.useRememberedPassword && payload.username === remembered.username ? readPasswordBlob(remembered) : undefined);
        if (!password) throw new Error("请填写密码，或重新启用已保存的密码。");
        const ctx = loginCtx ?? (await beginLogin());
        loginCtx = null;
        const result = await completeLogin(ctx, {
          username: payload.username,
          password,
          captchaCode: payload.captchaCode,
        });

        const client = makeClient(result.jar);
        const profile = await verifySession(client);
        if (!profile) {
          return {
            ok: false,
            error: {
              kind: "protocol",
              message: "登录已通过认证服务器，但 eLearning 会话无效。",
            },
          };
        }

        saveSession(sessionPath(), result.jar, {
          username: payload.username,
          displayName: profile.name,
        });

        const prefs = readPrefs();
        prefs.username = payload.username;
        prefs.rememberUsername = true;
        if (payload.remember) {
          prefs.rememberPassword = true;
          const blob = passwordBlob(password);
          prefs.encryptedPassword = blob;
          if (!blob) credentials().warning = "系统安全存储不可用，密码仅用于本次登录。";
        } else {
          prefs.rememberPassword = false;
          prefs.encryptedPassword = undefined;
        }
        writePrefs(prefs);

        accountEpoch++;
        lectureService?.reset();
        syncPaused = false;
        snapshot = null;
        // A cached account must never be shown while the new account loads.
        if (existsSync(snapshotPath())) atomicJson(snapshotPath(), {});
        return { ok: true, data: { profile } };
      } catch (err) {
        return fail(err);
      }
    },
  );

  handle(
    "auth:status",
    async (): Promise<
      IpcResult<{
        loggedIn: boolean;
        profile?: CanvasProfile;
        savedAt?: string;
      }>
    > => {
      if (DEMO) {
        const demo = buildDemoSnapshot();
        return {
          ok: true,
          data: {
            loggedIn: true,
            profile: demo.profile,
            savedAt: demo.fetchedAt,
          },
        };
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
    },
  );

  handle(
    "auth:remembered",
    (): { username?: string; hasRememberedPassword: boolean; storageWarning?: string } => {
      const prefs = readPrefs();
      return {
        username: prefs.rememberUsername ? prefs.username : undefined,
        hasRememberedPassword: !!readPasswordBlob(prefs),
        storageWarning: credentials().warning,
      };
    },
  );

  handle("auth:logout", (): IpcResult<true> => {
    try {
      const prefs = readPrefs();
      prefs.encryptedPassword = undefined;
      writePrefs(prefs);
      credentials().clearSession(sessionPath());
      accountEpoch++;
      lectureService?.reset();
      syncPaused = true;
      snapshot = null;
      if (existsSync(snapshotPath())) atomicJson(snapshotPath(), {});
      return { ok: true, data: true };
    } catch (err) {
      return fail(err);
    }
  });

  handle(
    "data:snapshot",
    async (
      _e,
      opts: { force?: boolean; full?: boolean } = {},
    ): Promise<IpcResult<Snapshot>> => {
      try {
        return {
          ok: true,
          data: await synchronize(opts.force === true, opts.full === true),
        };
      } catch (err) {
        return fail(err);
      }
    },
  );

  handle("data:cached", (): Snapshot | null => {
    // 演示模式也要把快照存进模块变量：否则渲染进程拿到了数据，
    // 主进程这边的 `snapshot` 仍是 null，任何按 id 查作业的功能
    //（比如作业详情）都会查不到东西。
    if (DEMO) {
      snapshot = buildDemoSnapshot();
      seedDemoWorkspace(snapshot);
      return snapshot;
    }
    if (!snapshot) snapshot = readCachedSnapshot();
    return snapshot;
  });

  /** Escape hatch used by the error screen: forget cache and session. */
  handle("data:clear", (): IpcResult<true> => {
    try {
      accountEpoch++;
      lectureService?.reset();
      snapshot = null;
      credentials().clearSession(sessionPath());
      for (const file of [snapshotPath()]) {
        if (existsSync(file)) writeFileSync(file, "{}", "utf8");
      }
      return { ok: true, data: true };
    } catch (err) {
      return fail(err);
    }
  });

  handle("shell:open", async (_e, url: string): Promise<void> => {
    try {
      const parsed = new URL(url);
      if (parsed.protocol === "https:" && !parsed.username && !parsed.password)
        await shell.openExternal(parsed.href);
    } catch { /* Invalid and non-HTTPS links never leave the app. */ }
  });

  // --- 课程文件 ------------------------------------------------------------

  /**
   * 已取回的课程文件树。
   *
   * 缓存在主进程里有两个原因：界面上反复展开收起不该反复打接口；
   * 下载时也只接受渲染进程传来的 courseId + fileIds，
   * 磁盘路径一律由主进程自己算，避免信任渲染进程给的路径。
   */
  const fileTreeCache = new Map<string, FileNode>();

  async function getCourseFileTree(
    courseId: number,
    force = false,
  ): Promise<FileNode> {
    const owner = activeAccount();
    if (!snapshot?.courses.some((c) => c.id === courseId))
      throw new Error("当前账号无此课程");
    const cacheKey = `${owner}:${courseId}`;
    if (DEMO) return buildDemoFileTree(courseId);
    if (!force && fileTreeCache.has(cacheKey))
      return fileTreeCache.get(cacheKey)!;
    const jar = currentJar();
    if (!jar) throw new Error("尚未登录");
    const client = makeClient(jar);
    const [folders, files] = await Promise.all([
      client.getCourseFolders(courseId),
      client.getCourseFiles(courseId),
    ]);
    const tree = buildFileTree(folders, files);
    if (snapshot?.profile.id !== owner) throw new Error("账号已切换");
    fileTreeCache.set(cacheKey, tree);
    return tree;
  }

  handle(
    "files:course",
    async (
      _e,
      args: { courseId: number; force?: boolean },
    ): Promise<
      IpcResult<{ tree: FileNode; stats: { count: number; bytes: number } }>
    > => {
      try {
        const tree = await getCourseFileTree(
          args.courseId,
          args.force === true,
        );
        return { ok: true, data: { tree, stats: treeStats(tree) } };
      } catch (err) {
        return fail(err);
      }
    },
  );

  handle(
    "files:root",
    (): string => readPrefs().downloadRoot ?? defaultDownloadRoot(),
  );

  /** 侧边栏底部显示版本号，免得装了两版看起来一样分不清。 */
  handle("app:version", (): string => app.getVersion());

  // --- 作业详情与简介 -------------------------------------------------------

  /** 大模型配置（读）。API key 只在主进程里用，不主动回传渲染进程全文。 */
  const publicLlm = (cfg: LlmConfig) => ({ baseUrl: cfg.baseUrl, model: cfg.model, enabled: cfg.enabled, hasApiKey: !!cfg.apiKey, storageWarning: credentials().warning });
  handle("llm:get", () => {
    const cfg = readPrefs().llm ?? DEFAULT_LLM;
    // 回传时把 key 打码，界面上只需要知道「配没配」。
    return publicLlm(cfg);
  });

  handle(
    "llm:set",
    (
      _e,
      patch: Partial<LlmConfig> & { clearApiKey?: boolean },
    ) => {
      try {
        const current = readPrefs().llm ?? DEFAULT_LLM;
        // 传进来的是打码串说明用户没改 key，保留原来的。
        const nextKey =
          patch.clearApiKey ? "" : !patch.apiKey || patch.apiKey === "********"
            ? current.apiKey
            : patch.apiKey.trim();
        const next: LlmConfig = {
          baseUrl: (patch.baseUrl ?? current.baseUrl)
            .trim()
            .replace(/\/+$/, ""),
          model: (patch.model ?? current.model).trim(),
          enabled: patch.enabled ?? current.enabled,
          apiKey: nextKey,
        };
        writePrefs({ ...readPrefs(), llm: next });
        return {
          ok: true,
          data: publicLlm(next),
        };
      } catch (err) {
        return fail(err);
      }
    },
  );

  /**
   * 取作业详情并生成简介。
   *
   * 完整描述按需拉取（列表里只存了摘录），简介会缓存——
   * 同一份描述只花一次大模型调用。
   */
  handle(
    "assignment:detail",
    async (
      _e,
      args: { courseId: number; assignmentId: number },
    ): Promise<
      IpcResult<{
        description: string;
        summary: string;
        summarySource: "llm" | "fallback" | "none";
        summaryError?: string;
        cached: boolean;
      }>
    > => {
      try {
        // 演示模式：没有会话可拉接口，直接用快照里存的摘录。
        if (DEMO) {
          const row = snapshot?.assignments.find(
            (a) => a.id === args.assignmentId,
          );
          const desc = row?.descriptionExcerpt ?? "";
          return {
            ok: true,
            data: {
              description: desc,
              summary: fallbackSummary(desc),
              summarySource: "fallback" as const,
              cached: false,
            },
          };
        }

        const jar = currentJar();
        if (!jar) throw new Error("尚未登录");
        const client = makeClient(jar);
        const assignment = await client.getAssignment(
          args.courseId,
          args.assignmentId,
        );
        const description = assignment.description ?? "";

        const prefs = readPrefs();
        const cfg = prefs.llm ?? DEFAULT_LLM;
        const key = `${activeAccount()}:${summaryCacheKey(args.assignmentId, description)}`;
        const cache = { ...(prefs.summaryCache ?? {}) };

        if (cache[key]) {
          return {
            ok: true,
            data: {
              description,
              summary: cache[key],
              summarySource: cfg.enabled ? "llm" : "fallback",
              cached: true,
            },
          };
        }

        const result = await summarizeAssignment(
          assignment.name,
          description,
          cfg,
        );
        if (result.summary) {
          cache[key] = result.summary;
          // 缓存别无限长：按插入顺序裁掉最早的。
          const keys = Object.keys(cache);
          if (keys.length > 400)
            for (const k of keys.slice(0, keys.length - 400)) delete cache[k];
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
    },
  );

  /** 只算简介，不重新拉描述——详情页已经有描述时用。 */
  handle(
    "assignment:summarise",
    async (
      _e,
      args: { assignmentId: number; name: string; description: string },
    ): Promise<
      IpcResult<{
        summary: string;
        summarySource: "llm" | "fallback" | "none";
        summaryError?: string;
      }>
    > => {
      try {
        const prefs = readPrefs();
        const cfg = prefs.llm ?? DEFAULT_LLM;
        const result = await summarizeAssignment(
          args.name,
          args.description,
          cfg,
        );
        if (result.summary) {
          const cache = { ...(prefs.summaryCache ?? {}) };
          cache[
            `${activeAccount()}:${summaryCacheKey(args.assignmentId, args.description)}`
          ] = result.summary;
          writePrefs({ ...prefs, summaryCache: cache });
        }
        return {
          ok: true,
          data: {
            summary: result.summary,
            summarySource: result.source,
            summaryError: result.error,
          },
        };
      } catch (err) {
        return fail(err);
      }
    },
  );

  handle("files:pickRoot", async (): Promise<IpcResult<string>> => {
    try {
      const res = await dialog.showOpenDialog({
        title: "选择课程文件的下载位置",
        defaultPath: readPrefs().downloadRoot ?? defaultDownloadRoot(),
        properties: ["openDirectory", "createDirectory"],
      });
      if (res.canceled || res.filePaths.length === 0)
        return { ok: false, error: { kind: "cancelled", message: "已取消" } };
      const picked = res.filePaths[0];
      writePrefs({ ...readPrefs(), downloadRoot: picked });
      return { ok: true, data: picked };
    } catch (err) {
      return fail(err);
    }
  });

  let activeDownload: DownloadManager | null = null;

  handle("files:cancel", (): IpcResult<true> => {
    activeDownload?.cancel();
    activeDownload = null;
    return { ok: true, data: true };
  });

  handle(
    "files:download",
    async (
      _e,
      args: { courseId: number; fileIds?: number[] },
    ): Promise<IpcResult<DownloadProgress>> => {
      try {
        if (activeDownload)
          return {
            ok: false,
            error: { kind: "busy", message: "已有下载任务在进行中" },
          };

        // 演示模式：不联网、不落盘，只把进度条演一遍。
        if (DEMO) return await simulateDemoDownload(args, mainWindow);

        const jar = currentJar();
        if (!jar) throw new Error("尚未登录");

        const course = snapshot?.courses.find((c) => c.id === args.courseId);
        const termName = course?.termName || "未分学期";
        const courseName =
          course?.displayName || course?.name || `课程 ${args.courseId}`;

        const tree = await getCourseFileTree(args.courseId);
        const all = flattenFiles(tree);
        const wanted =
          args.fileIds && args.fileIds.length > 0
            ? all.filter((n) => n.file && args.fileIds!.includes(n.file.id))
            : all;

        if (wanted.length === 0) {
          return {
            ok: false,
            error: { kind: "empty", message: "这门课没有可下载的文件" },
          };
        }

        // 由主进程自己算磁盘路径，渲染进程只提供 fileId。
        const plan = planDownloadPaths(
          termName,
          courseName,
          wanted.map((n) => {
            const slash = n.path.lastIndexOf("/");
            return {
              folderPath: slash < 0 ? "" : n.path.slice(0, slash),
              fileName: n.name,
              file: n.file!,
            };
          }),
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
        mainWindow?.webContents.send("files:progress", {
          total: items.length,
          completed: 0,
          skipped: 0,
          failed: 0,
          currentName: "",
          bytesReceived: 0,
          bytesTotal: items.reduce((s, i) => s + (i.size > 0 ? i.size : 0), 0),
          currentReceived: 0,
          currentTotal: 0,
          errors: [],
          state: "running",
        } satisfies DownloadProgress);

        const mgr = new DownloadManager({
          jar,
          root,
          onProgress: (p) => mainWindow?.webContents.send("files:progress", p),
        });
        activeDownload = mgr;
        const result = await mgr.run(items);
        activeDownload = null;

        // 全部成功且无跳过时，顺便把目录打开给用户看一眼。
        if (result.failed === 0) {
          const firstSlash = items[0].relativePath.indexOf("/");
          const termDir = join(
            root,
            firstSlash > 0 ? items[0].relativePath.slice(0, firstSlash) : "",
          );
          void shell.openPath(termDir);
        }
        return { ok: true, data: result };
      } catch (err) {
        activeDownload = null;
        return fail(err);
      }
    },
  );

  handle(
    "files:reveal",
    async (_e, relativePath: string): Promise<void> => {
      try {
        const root = readPrefs().downloadRoot ?? defaultDownloadRoot();
        const target = resolve(root, relativePath), within = relative(resolve(root), target);
        if (within.startsWith("..") || isAbsolute(within)) throw Error("下载路径无效");
        shell.showItemInFolder(target);
      } catch {
        // 路径无效时静默忽略：这只是个便利功能。
      }
    },
  );
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
    if (typeof wc.invalidate === "function") wc.invalidate();
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
  const smokeH = Number(process.env["ELEARNING_SMOKE_HEIGHT"] ?? 0);
  const smokeW = Number(process.env["ELEARNING_SMOKE_WIDTH"] ?? 0);

  mainWindow = new BrowserWindow({
    width: smokeW > 0 ? smokeW : 1360,
    height: smokeH > 0 ? smokeH : 900,
    minWidth: 800,
    minHeight: 600,
    show: false,
    autoHideMenuBar: true,
    backgroundColor: "#0d1220",
    title: "复旦大学 eLearning 学习看板",
    webPreferences: {
      preload: join(__dirname, "../preload/index.js"),
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false,
      // Only automated screenshots need unthrottled hidden rendering.
      backgroundThrottling: !process.env["ELEARNING_SMOKE"],
    },
  });

  mainWindow.on("close", (e) => {
    if (!quitting && readPrefs().closeToTray) {
      e.preventDefault();
      mainWindow?.hide();
      if (!trayNotice) {
        trayNotice = true;
        void dialog.showMessageBox({
          type: "info",
          message: "应用仍在托盘运行",
          detail:
            "同步与已开启的提醒会继续。要完全退出，请使用托盘菜单中的退出。",
        });
      }
    }
  });
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
  mainWindow.on("ready-to-show", () => mainWindow?.show());
  if (DEMO && process.env['ELEARNING_LIFECYCLE_TEST']) {
    mainWindow.webContents.once('did-finish-load', () => { setTimeout(() => {
      const reportPath = process.env['ELEARNING_LIFECYCLE_TEST']!;
      try {
        writePrefs({ ...readPrefs(), closeToTray: true });
        configureLifecycle();
        trayNotice = true; // Do not block the automated run on the first-close explanation.
        const window = mainWindow!;
        window.close();
        if (window.isDestroyed() || window.isVisible() || !tray || tray.isDestroyed()) throw new Error('Close-to-tray failed');
        showWindow();
        if (!window.isVisible()) throw new Error('Tray restore failed');
        const report = { trayClose: true, restore: true, explicitQuit: false, packaged: app.isPackaged, notificationSupported: Notification.isSupported() };
        app.once('will-quit', () => { report.explicitQuit = true; atomicJson(reportPath, report); });
        app.quit();
      } catch (e) { atomicJson(reportPath, { error: String(e) }); app.exit(1); }
    }, 1000); });
  }

  // Surface renderer-side problems in the terminal while developing.
  if (!app.isPackaged) {
    mainWindow.webContents.on(
      "console-message",
      (_e, level, message, line, source) => {
        console.log(`[renderer:${level}] ${message}  (${source}:${line})`);
      },
    );
  }
  mainWindow.webContents.on("did-fail-load", (_e, code, desc, url) => {
    console.error(`[renderer] failed to load ${url}: ${code} ${desc}`);
  });
  mainWindow.webContents.on("render-process-gone", (_e, details) => {
    console.error(`[renderer] process gone: ${details.reason}`);
  });

  // Smoke mode: screenshot the first screen and exit, so the UI can be checked
  // without a human at the keyboard.
  if (process.env["ELEARNING_SMOKE"]) {
    mainWindow.webContents.once("did-finish-load", () => {
      const delay = Number(process.env["ELEARNING_SMOKE_DELAY"] ?? 5000);
      setTimeout(() => {
        void (async () => {
          try {
            // Optionally drive the UI first, so any screen can be captured.
            const scriptFile = process.env["ELEARNING_SMOKE_SCRIPT_FILE"];
            const script = scriptFile
              ? readFileSync(scriptFile, "utf8")
              : process.env["ELEARNING_SMOKE_SCRIPT"];
            if (script) {
              const view = JSON.stringify(
                process.env["ELEARNING_SMOKE_VIEW"] ?? "dashboard",
              );
              try {
                const result = await mainWindow!.webContents.executeJavaScript(
                  `const SMOKE_VIEW = ${view};\n${script}`,
                );
                console.log("[smoke] driver result:", result);
              } catch (err) {
                // A broken driver must not cost us the screenshot.
                console.error("[smoke] driver threw:", (err as Error).message);
              }
              await new Promise((r) =>
                setTimeout(
                  r,
                  Number(process.env["ELEARNING_SMOKE_SETTLE"] ?? 2500),
                ),
              );
            }
            const image = await captureFresh(mainWindow!);
            const out = join(
              process.cwd(),
              process.env["ELEARNING_SMOKE"] as string,
            );
            writeFileSync(out, image.toPNG());
            console.log(`[smoke] screenshot written to ${out}`);
          } catch (err) {
            console.error("[smoke] capture failed:", err);
          } finally {
            app.exit(0);
          }
        })();
      }, delay);
    });
  }

  // Never let the app navigate away from its own UI.
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    const external = safeExternalUrl(url);
    if (external) void shell.openExternal(external);
    return { action: "deny" };
  });

  mainWindow.webContents.on("will-navigate", event => event.preventDefault());
  const devUrl = process.env["ELECTRON_RENDERER_URL"];
  if (devUrl) {
    void mainWindow.loadURL(devUrl);
  } else {
    void mainWindow.loadFile(join(__dirname, "../renderer/index.html"));
  }
}

app.whenReady().then(() => {
  ensureUserDir();
  powerMonitor.on("resume", () => mainWindow?.webContents.send("app:resume"));
  registerIpc();
  createWindow();
  app.setAppUserModelId("cn.edu.fudan.elearning.dashboard");
  configureLifecycle();
  reminderTimer = setInterval(() => checkReminders(false), 60000);
  powerMonitor.on("resume", () => checkReminders(true));

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

let tray: Tray | null = null;
let quitting = false,
  trayNotice = false,
  remindersPaused = false;
let syncTimer: ReturnType<typeof setInterval> | undefined;
let reminderTimer: ReturnType<typeof setInterval> | undefined;
function showWindow() {
  if (!mainWindow) createWindow();
  mainWindow?.show();
  mainWindow?.restore();
  mainWindow?.focus();
}
function notify(
  title: string,
  body: string,
  account: number,
  target: Record<string, string>,
) {
  if (!Notification.isSupported()) return;
  const n = new Notification({ title, body });
  n.on("click", () => {
    if (snapshot?.profile.id !== account) return;
    showWindow();
    mainWindow?.webContents.send("workspace:navigate", target);
  });
  n.show();
}
function configureLifecycle() {
  if (syncTimer) clearInterval(syncTimer);
  const prefs = readPrefs(),
    minutes = prefs.syncMinutes ?? 15;
  if (minutes && !DEMO)
    syncTimer = setInterval(() => {
      if (snapshot)
        void synchronize(true, false, !syncPaused && !!currentJar()).catch((e) => {
          if (e instanceof LoginError && e.kind === "session_expired")
            syncPaused = true;
          mainWindow?.webContents.send("workspace:navigate", {
            error: describeCanvasError(e),
          });
        });
    }, minutes * 60000);
  if (prefs.closeToTray && !tray) {
    const icon = nativeImage.createFromPath(
      app.isPackaged
        ? join(process.resourcesPath, "icon.png")
        : join(__dirname, "../../build/icon.png"),
    );
    tray = new Tray(
      icon.isEmpty()
        ? nativeImage.createFromDataURL(
            "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
          )
        : icon,
    );
    tray.setToolTip("复旦 eLearning");
    tray.on("double-click", showWindow);
  }
  if (tray && !prefs.closeToTray) {
    tray.destroy();
    tray = null;
  }
  tray?.setContextMenu(
    Menu.buildFromTemplate([
      { label: "打开", click: showWindow },
      {
        label: "立即同步",
        click: () => {
          void synchronize(true, false, !syncPaused && !!currentJar()).catch((e) => {
            showWindow();
            mainWindow?.webContents.send("workspace:navigate", {
              error: describeCanvasError(e),
            });
          });
        },
      },
      {
        label: "暂停提醒",
        type: "checkbox",
        checked: remindersPaused,
        click: (item) => {
          remindersPaused = item.checked;
        },
      },
      { type: "separator" },
      {
        label: "退出",
        click: () => {
          quitting = true;
          app.quit();
        },
      },
    ]),
  );
}
function checkReminders(resume: boolean) {
  if (!snapshot || remindersPaused || !readPrefs().taskNotifications) return;
  try {
    const store = workspaceStore(),
      data = store.read(snapshot.profile.id),
      now = Date.now();
    const plan = dueReminders(unifyTasks(snapshot, data, now + 366 * 86400000), data.delivered, now, resume);
    const due = plan.due;
    if (due.length) {
      data.delivered = plan.delivered;
      store.write(data);
      notify(
        `${due.length} 项任务提醒`,
        due
          .slice(0, 3)
          .map((t) => t.title)
          .join("、"),
        snapshot.profile.id,
        { page: "tasks", task: due[0].id },
      );
    }
  } catch (e) {
    mainWindow?.webContents.send("workspace:navigate", {
      error: `提醒保存失败：${String(e)}`,
    });
  }
}
app.on("before-quit", () => {
  quitting = true;
  lectureService?.dispose();
  if (syncTimer) clearInterval(syncTimer);
  if (reminderTimer) clearInterval(reminderTimer);
  tray?.destroy();
});

function seedDemoWorkspace(s: Snapshot) {
  const path = join(userDir(), "accounts", `workspace-${s.profile.id}.json`);
  if (existsSync(path)) return;
  const data = emptyWorkspace(s.profile.id),
    now = new Date().toISOString();
  data.series.push({
    id: "demo-review",
    title: "整理本周课堂笔记",
    notes: "补全课堂讨论的论点，检查参考文献。",
    courseId: null,
    dueAt: new Date(Date.now() + 2 * 86400000).toISOString(),
    repeat: "weekly",
    weekdays: [2, 6],
    endDate: null,
    checklist: [
      { id: "read", title: "阅读课堂材料" },
      { id: "notes", title: "补全笔记" },
    ],
    reminders: [60],
    createdAt: now,
    exceptions: {},
  });
  const c =
    s.courses.find((c) => s.terms.find((t) => t.isCurrent)?.id === c.termId) ??
    s.courses[0];
  for (const [kind, title, before, after] of [
    [
      "assignment",
      "阅读报告截止时间调整",
      { dueAt: "2026-10-20T23:59:00+08:00" },
      { dueAt: "2026-10-23T23:59:00+08:00" },
    ],
    ["grade", "第一次实验成绩已发布", { score: null }, { score: 92 }],
    [
      "announcement",
      "下周课堂讨论安排",
      null,
      { message: "请提前阅读第六章，并准备两个讨论问题。" },
    ],
    [
      "file",
      "第六章讲义已更新",
      { name: "第六章.pdf", size: 102400 },
      { name: "第六章.pdf", size: 124800 },
    ],
  ] as const)
    data.changes.push({
      id: `demo-${kind}`,
      batch: "demo-batch",
      at: now,
      courseId: c.id,
      kind,
      title,
      before: before === null ? null : JSON.stringify(before),
      after: JSON.stringify(after),
      read: false,
      objectId: "demo",
    });
  workspaceStore().write(data);
}
