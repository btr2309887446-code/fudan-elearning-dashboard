import type { CanvasFile, FileNode } from '../core/files';
import type { DownloadProgress } from '../main/download';
import type { CanvasProfile, Snapshot } from '../core/types';

export type IpcResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: { kind: string; message: string; detail?: string } };

export interface Prefs {
  rememberUsername: boolean;
  username?: string;
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
  /** 手动标记为「无需提交」的作业键（`courseId:assignmentId`）。只影响显示。 */
  ignoredAssignments?: string[];
}

export type { CanvasFile, DownloadProgress, FileNode };

export interface ElearningApi {
  prefs: {
    get(): Promise<Prefs>;
    set(patch: Partial<Prefs>): Promise<Prefs>;
  };
  auth: {
    prepare(username: string): Promise<IpcResult<{ captchaRequired: boolean; captchaImage?: string }>>;
    checkCaptcha(username: string): Promise<IpcResult<{ captchaRequired: boolean; captchaImage?: string }>>;
    submit(payload: {
      username: string;
      password: string;
      captchaCode?: string;
      remember?: boolean;
    }): Promise<IpcResult<{ profile: CanvasProfile }>>;
    status(): Promise<IpcResult<{ loggedIn: boolean; profile?: CanvasProfile; savedAt?: string }>>;
    remembered(): Promise<{ username?: string; password?: string }>;
    logout(): Promise<IpcResult<true>>;
  };
  data: {
    snapshot(opts?: { force?: boolean }): Promise<IpcResult<Snapshot>>;
    cached(): Promise<Snapshot | null>;
    /** Forget the local cache and saved session (recovery from a bad state). */
    clear(): Promise<IpcResult<true>>;
    onProgress(cb: (p: { done: number; total: number; label: string }) => void): () => void;
  };
  /** 课程文件：浏览、下载、选择下载位置。 */
  files: {
    /** 取回某门课的文件/文件夹树。 */
    course(courseId: number, force?: boolean): Promise<IpcResult<{ tree: FileNode; stats: { count: number; bytes: number } }>>;
    /** 开始下载。不传 fileIds 表示整门课；返回最终进度。 */
    download(courseId: number, fileIds?: number[]): Promise<IpcResult<DownloadProgress>>;
    /** 取消进行中的下载。 */
    cancel(): Promise<IpcResult<true>>;
    /** 当前下载根目录。 */
    root(): Promise<string>;
    /** 弹出目录选择框；取消时返回 ok:false, kind:'cancelled'。 */
    pickRoot(): Promise<IpcResult<string>>;
    /** 在资源管理器里定位到某个已下载的文件。 */
    reveal(relativePath: string): Promise<void>;
    /** 订阅下载进度；返回退订函数。 */
    onProgress(cb: (p: DownloadProgress) => void): () => void;
  };
  open(url: string): Promise<void>;
  /** 应用版本号（来自 package.json），显示在侧边栏底部。 */
  version(): Promise<string>;
  /** 作业详情与 100 字简介。 */
  assignment: {
    detail(
      courseId: number,
      assignmentId: number
    ): Promise<
      IpcResult<{
        description: string;
        summary: string;
        summarySource: 'llm' | 'fallback' | 'none';
        summaryError?: string;
        cached: boolean;
      }>
    >;
    summarise(payload: {
      assignmentId: number;
      name: string;
      description: string;
    }): Promise<IpcResult<{ summary: string; summarySource: 'llm' | 'fallback' | 'none'; summaryError?: string }>>;
  };
  /** 大模型配置。apiKey 回传时是打码串，不是真实密钥。 */
  llm: {
    get(): Promise<{ baseUrl: string; model: string; enabled: boolean; apiKey: string }>;
    set(patch: {
      baseUrl?: string;
      model?: string;
      enabled?: boolean;
      apiKey?: string;
    }): Promise<IpcResult<{ baseUrl: string; model: string; enabled: boolean; apiKey: string }>>;
  };
}

declare global {
  interface Window {
    elearning: ElearningApi;
  }
}
