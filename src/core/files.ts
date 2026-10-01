/**
 * 课程文件与文件夹。
 *
 * 分成两层：
 *  - 纯函数：构建目录树、把 Canvas 的文件夹层级映射成磁盘路径、净化文件名。
 *    这些不含任何网络或平台 API，可以直接单元测试。
 *  - 取数：挂在 CanvasClient 上的两个 list 接口。
 *
 * 磁盘路径的约定（与界面里的学期分组一致）：
 *
 *   根目录 / 学期 / 课程 / Canvas 里的子文件夹... / 文件名
 *
 * 例：D:\eLearning\2026-2027 学年第一学期\CS100113.02 程序设计基础\课件\第1章.pdf
 */

import type { CanvasClient } from './canvas.ts';

// ---------------------------------------------------------------------------
// 类型
// ---------------------------------------------------------------------------

export interface CanvasFolder {
  id: number;
  name: string;
  /** Canvas 给的全名，形如 "course files/课件"；不同部署会本地化。 */
  fullName: string;
  parentFolderId: number | null;
  filesCount: number;
  foldersCount: number;
  /** Canvas 自己的排序位。按它排才能得到「第一章、第二章」而不是拼音序。 */
  position: number | null;
}

export interface CanvasFile {
  id: number;
  folderId: number | null;
  displayName: string;
  filename: string;
  contentType: string;
  /** 带 verifier 的限时下载地址，必须来自接口响应，不能缓存复用。 */
  url: string;
  size: number;
  createdAt: string;
  updatedAt: string;
  locked: boolean;
  hidden: boolean;
}

/** 目录树节点，界面与下载都基于它。 */
export interface FileNode {
  kind: 'folder' | 'file';
  /** 净化后的名字（可直接用作磁盘上的文件名）。 */
  name: string;
  /** 相对课程根目录的路径，用 '/' 分隔。 */
  path: string;
  size?: number;
  contentType?: string;
  /** 文件夹在 Canvas 里的排序位（仅文件夹有）。 */
  position?: number | null;
  file?: CanvasFile;
  children: FileNode[];
}

export interface CourseFiles {
  folders: CanvasFolder[];
  files: CanvasFile[];
}

// ---------------------------------------------------------------------------
// 文件名净化
// ---------------------------------------------------------------------------

/** Windows 保留的设备名，不能作为文件名。 */
const RESERVED_NAMES = new Set([
  'con', 'prn', 'aux', 'nul',
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
]);

/**
 * 把一个路径段净化成各平台都能用的名字。
 *
 * 同时兼顾 Windows / macOS / Linux 的限制：
 *  - Windows 禁止 `\ / : * ? " < > |` 与控制字符；
 *  - Windows 不允许结尾是点或空格；
 *  - Windows 保留 CON、PRN 等设备名（带扩展名也算，如 `CON.txt`）；
 *  - 单段过长会超出路径上限，截断到 120 字符。
 */
export function sanitizeSegment(raw: string): string {
  let name = (raw ?? '').trim();

  // 控制字符与非法字符统一换成下划线。
  // eslint-disable-next-line no-control-regex
  name = name.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_');

  // 连续的空白压成一个空格，避免出现奇怪的长文件名。
  name = name.replace(/\s+/g, ' ').trim();

  // Windows 不允许结尾是点或空格。
  name = name.replace(/[. ]+$/, '');

  if (name.length > 120) {
    // 尽量保留扩展名。
    const dot = name.lastIndexOf('.');
    if (dot > 0 && name.length - dot <= 12) {
      const ext = name.slice(dot);
      name = name.slice(0, 120 - ext.length) + ext;
    } else {
      name = name.slice(0, 120);
    }
  }

  if (name.length === 0) return '_';

  // 保留设备名：加前缀而不是改名，保留可读性。
  const stem = name.includes('.') ? name.slice(0, name.indexOf('.')) : name;
  if (RESERVED_NAMES.has(stem.toLowerCase())) name = `_${name}`;

  return name;
}

/** 净化一整条相对路径（按 '/' 分段）。 */
export function sanitizePath(relativePath: string): string {
  return relativePath
    .split('/')
    .filter((s) => s.length > 0 && s !== '.' && s !== '..')
    .map(sanitizeSegment)
    .join('/');
}

/**
 * 在同一目录内去重。
 *
 * 输入是相对路径列表，返回不会互相覆盖的路径列表：
 * 重名的第二个变成 `名字 (2).ext`，以此类推。
 *
 * 比较时忽略大小写——Windows 与 macOS 默认都不区分大小写，
 * 而 `A.pdf` 与 `a.pdf` 落盘后会互相覆盖。
 */
export function dedupePaths(paths: string[]): string[] {
  const used = new Set<string>();
  const out: string[] = [];

  for (const p of paths) {
    const slash = p.lastIndexOf('/');
    const dir = slash < 0 ? '' : p.slice(0, slash + 1);
    const base = slash < 0 ? p : p.slice(slash + 1);

    // 只有非隐藏文件（点不在开头）才拆扩展名，否则 ".gitignore" 会被拆坏。
    const dot = base.lastIndexOf('.');
    const hasExt = dot > 0;
    const stem = hasExt ? base.slice(0, dot) : base;
    const ext = hasExt ? base.slice(dot) : '';

    let candidate = p;
    let n = 2;
    while (used.has(candidate.toLowerCase())) {
      candidate = `${dir}${stem} (${n})${ext}`;
      n += 1;
    }

    used.add(candidate.toLowerCase());
    out.push(candidate);
  }
  return out;
}

/**
 * 自然序比较：把名字里的数字当数字比，而不是当字符比。
 *
 * 这样 `第2章` 排在 `第10章` 前面（纯字典序会反过来）。
 *
 * 非数字部分用**码位序**，刻意不用 `localeCompare('zh-Hans-CN')`：
 * Dart 没有内置的拼音排序，桌面端若按拼音排、移动端按码位排，
 * 同一份文件在两端顺序会不一样。统一成码位序至少是可预测的。
 * 真正影响观感的文件夹顺序由 Canvas 的 position 决定，不受此影响。
 */
export function naturalCompare(a: string, b: string): number {
  const re = /(\d+)|(\D+)/g;
  const ax = a.match(re) ?? [];
  const bx = b.match(re) ?? [];
  for (let i = 0; i < Math.min(ax.length, bx.length); i += 1) {
    const an = /^\d+$/.test(ax[i]);
    const bn = /^\d+$/.test(bx[i]);
    if (an && bn) {
      const d = Number(ax[i]) - Number(bx[i]);
      if (d !== 0) return d;
    } else if (ax[i] !== bx[i]) {
      return ax[i] < bx[i] ? -1 : 1;
    }
  }
  return ax.length - bx.length;
}

// ---------------------------------------------------------------------------
// 目录树
// ---------------------------------------------------------------------------

/**
 * 由扁平的文件夹与文件列表构建树。
 *
 * 用 parent_folder_id 串层级，而不是解析 full_name——
 * 后者带本地化的根名（"course files" / "课程文件"），解析起来不可靠。
 */
export function buildFileTree(folders: CanvasFolder[], files: CanvasFile[]): FileNode {
  const byId = new Map<number, FileNode>();

  const root: FileNode = { kind: 'folder', name: '', path: '', children: [] };

  for (const f of folders) {
    byId.set(f.id, {
      kind: 'folder',
      name: sanitizeSegment(f.name),
      path: '',
      position: f.position,
      children: [],
    });
  }

  // 先接父子关系，再补 path（父的 path 必须先算好）。
  const parentOf = new Map<number, number | null>();
  for (const f of folders) parentOf.set(f.id, f.parentFolderId);

  const pathOf = (id: number, depth = 0): string => {
    const node = byId.get(id);
    if (!node) return '';
    if (node.path) return node.path;
    // 正常数据不会有环；万一有，也不能把递归撑爆。
    if (depth > 64) {
      node.path = node.name;
      return node.path;
    }
    const parent = parentOf.get(id) ?? null;
    const parentPath = parent != null && byId.has(parent) ? pathOf(parent, depth + 1) : '';
    node.path = parentPath ? `${parentPath}/${node.name}` : node.name;
    return node.path;
  };

  for (const f of folders) {
    const node = byId.get(f.id)!;
    pathOf(f.id);
    const parent = f.parentFolderId;
    const bucket = parent != null && byId.has(parent) ? byId.get(parent)! : root;
    bucket.children.push(node);
  }

  for (const file of files) {
    const folder = file.folderId != null ? byId.get(file.folderId) : undefined;
    const name = sanitizeSegment(file.displayName || file.filename || `file-${file.id}`);
    const parentPath = folder?.path ?? '';
    (folder ?? root).children.push({
      kind: 'file',
      name,
      path: parentPath ? `${parentPath}/${name}` : name,
      size: file.size,
      contentType: file.contentType,
      file,
      children: [],
    });
  }

  // 目录在前；文件夹按 Canvas 的 position 排（这样才能得到「第一章、第二章」
  // 而不是拼音序「第二章、第一章」），文件按自然序排（第2章 在 第10章 之前）。
  const sortNode = (n: FileNode) => {
    n.children.sort((a, b) => {
      if (a.kind !== b.kind) return a.kind === 'folder' ? -1 : 1;
      if (a.kind === 'folder') {
        const ap = a.position ?? null;
        const bp = b.position ?? null;
        if (ap !== null && bp !== null && ap !== bp) return ap - bp;
        if (ap !== null && bp === null) return -1;
        if (ap === null && bp !== null) return 1;
      }
      return naturalCompare(a.name, b.name);
    });
    n.children.forEach(sortNode);
  };
  sortNode(root);

  return root;
}

/** 把树摊平成文件列表（下载时用）。 */
export function flattenFiles(node: FileNode): FileNode[] {
  const out: FileNode[] = [];
  const walk = (n: FileNode) => {
    if (n.kind === 'file') out.push(n);
    n.children.forEach(walk);
  };
  walk(node);
  return out;
}

/** 统计目录下的文件数与总字节数。 */
export function treeStats(node: FileNode): { count: number; bytes: number } {
  const files = flattenFiles(node);
  return {
    count: files.length,
    bytes: files.reduce((s, f) => s + (f.size ?? 0), 0),
  };
}

// ---------------------------------------------------------------------------
// Canvas 响应映射
// ---------------------------------------------------------------------------

function num(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : 0;
}

function str(v: unknown, fallback = ''): string {
  return typeof v === 'string' ? v : fallback;
}

export function folderFromJson(json: Record<string, unknown>): CanvasFolder {
  return {
    id: num(json.id),
    name: str(json.name, '未命名文件夹'),
    fullName: str(json.full_name),
    parentFolderId: json.parent_folder_id == null ? null : num(json.parent_folder_id),
    filesCount: num(json.files_count),
    foldersCount: num(json.folders_count),
    position: json.position == null ? null : num(json.position),
  };
}

export function fileFromJson(json: Record<string, unknown>): CanvasFile {
  return {
    id: num(json.id),
    folderId: json.folder_id == null ? null : num(json.folder_id),
    displayName: str(json.display_name) || str(json.filename) || `file-${num(json.id)}`,
    filename: str(json.filename),
    // Canvas 这个字段写作 "content-type"（带连字符），不是驼峰。
    contentType: str(json['content-type']) || str(json.content_type),
    url: str(json.url) || str(json.download_url),
    size: num(json.size),
    createdAt: str(json.created_at),
    updatedAt: str(json.updated_at) || str(json.modified_at),
    locked: json.locked === true || json.locked_for_user === true,
    hidden: json.hidden === true,
  };
}

// ---------------------------------------------------------------------------
// 磁盘路径
// ---------------------------------------------------------------------------

export interface DownloadTarget {
  /** 相对下载根目录的完整路径，用 '/' 分隔。 */
  relativePath: string;
  file: CanvasFile;
}

/**
 * 算出「学期 / 课程 / 子文件夹 / 文件名」这条相对路径。
 *
 * 传入的 filePaths 必须是同一个课程下的，这样重名才会在课程内被消解。
 */
export function planDownloadPaths(
  termName: string,
  courseName: string,
  entries: { folderPath: string; fileName: string; file: CanvasFile }[]
): DownloadTarget[] {
  const term = sanitizeSegment(termName);
  const course = sanitizeSegment(courseName);

  const raws = entries.map((e) => {
    const folder = sanitizePath(e.folderPath);
    const base = `${term}/${course}`;
    return folder ? `${base}/${folder}/${e.fileName}` : `${base}/${e.fileName}`;
  });

  const uniqued = dedupePaths(raws);
  return entries.map((e, i) => ({ relativePath: uniqued[i], file: e.file }));
}

/** 人类可读的字节数。 */
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
  const value = bytes / 1024 ** i;
  return `${value >= 100 || i === 0 ? Math.round(value) : value.toFixed(1)} ${units[i]}`;
}
