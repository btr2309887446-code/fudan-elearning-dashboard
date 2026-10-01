/**
 * 课程文件：浏览 + 下载。
 *
 * 交互约定：
 *  - 点文件夹行 → 展开/收起；
 *  - 点文件名 → 立刻下载这一个（这是「直接点击下载」）；
 *  - 勾选框 → 多选，顶部出现「下载选中」；
 *  - 「下载本课全部」→ 整门课。
 *
 * 下载路径由主进程决定（学期/课程/Canvas 子文件夹），
 * 这里只把 courseId 与 fileId 传过去，不参与路径拼接。
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { formatBytes, type FileNode } from '../../../core/files';
import type { DownloadProgress } from '../../../main/download';

interface Props {
  courseId: number;
}

/** 收集一个节点下所有文件的 id。 */
function fileIdsUnder(node: FileNode): number[] {
  const out: number[] = [];
  const walk = (n: FileNode) => {
    if (n.kind === 'file' && n.file) out.push(n.file.id);
    n.children.forEach(walk);
  };
  walk(node);
  return out;
}

export default function CourseFiles({ courseId }: Props) {
  const [tree, setTree] = useState<FileNode | null>(null);
  const [stats, setStats] = useState<{ count: number; bytes: number } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [expanded, setExpanded] = useState<Set<string>>(() => new Set(['']));
  const [selected, setSelected] = useState<Set<number>>(new Set());

  const [root, setRoot] = useState('');
  const [progress, setProgress] = useState<DownloadProgress | null>(null);
  const [result, setResult] = useState<DownloadProgress | null>(null);
  const [busy, setBusy] = useState(false);

  // 用 ref 保存订阅的退订函数，卸载时清理，避免切换课程后收到旧进度。
  const unsubRef = useRef<(() => void) | null>(null);

  const load = useCallback(
    async (force = false) => {
      setLoading(true);
      setError(null);
      const res = await window.elearning.files.course(courseId, force);
      if (res.ok) {
        setTree(res.data.tree);
        setStats(res.data.stats);
        // 默认展开第一层，让用户立刻看到内容。
        setExpanded(new Set(['', ...res.data.tree.children.filter((c) => c.kind === 'folder').map((c) => c.path)]));
      } else {
        setError(res.error.message);
      }
      setLoading(false);
    },
    [courseId]
  );

  useEffect(() => {
    setSelected(new Set());
    setResult(null);
    setProgress(null);
    void load();
  }, [load]);

  useEffect(() => {
    void window.elearning.files.root().then(setRoot);
    unsubRef.current = window.elearning.files.onProgress((p) => setProgress(p));
    return () => {
      unsubRef.current?.();
      unsubRef.current = null;
    };
  }, []);

  const startDownload = useCallback(
    async (fileIds?: number[]) => {
      setBusy(true);
      setResult(null);
      setProgress(null);
      const res = await window.elearning.files.download(courseId, fileIds);
      if (res.ok) {
        setResult(res.data);
        if (res.data.failed === 0) setSelected(new Set());
      } else {
        setError(res.error.message);
      }
      setBusy(false);
    },
    [courseId]
  );

  const toggleFolder = (path: string) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(path)) next.delete(path);
      else next.add(path);
      return next;
    });
  };

  const toggleFile = (id: number) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleNode = (node: FileNode) => {
    const ids = node.kind === 'file' && node.file ? [node.file.id] : fileIdsUnder(node);
    setSelected((prev) => {
      const next = new Set(prev);
      const allIn = ids.every((id) => next.has(id));
      ids.forEach((id) => (allIn ? next.delete(id) : next.add(id)));
      return next;
    });
  };

  const changeRoot = async () => {
    const res = await window.elearning.files.pickRoot();
    if (res.ok) setRoot(res.data);
  };

  const percent = useMemo(() => {
    if (!progress || progress.bytesTotal <= 0) return null;
    return Math.min(100, Math.round((progress.bytesReceived / progress.bytesTotal) * 100));
  }, [progress]);

  // --- 渲染 -----------------------------------------------------------------

  const renderNode = (node: FileNode, depth: number) => {
    const isFolder = node.kind === 'folder';
    const isOpen = expanded.has(node.path);
    const ids = isFolder ? fileIdsUnder(node) : node.file ? [node.file.id] : [];
    const allSelected = ids.length > 0 && ids.every((id) => selected.has(id));
    const someSelected = !allSelected && ids.some((id) => selected.has(id));

    return (
      <div key={node.kind + ':' + node.path}>
        <div className={`file-row${isFolder ? ' is-folder' : ''}`} style={{ paddingLeft: 10 + depth * 18 }}>
          <input
            type="checkbox"
            className="file-check"
            checked={allSelected}
            ref={(el) => {
              if (el) el.indeterminate = someSelected;
            }}
            onChange={() => toggleNode(node)}
            disabled={busy || ids.length === 0}
            title={isFolder ? '选中该文件夹下的全部文件' : '选中此文件'}
          />

          {isFolder ? (
            <button className="file-name as-button" onClick={() => toggleFolder(node.path)}>
              <span className={`file-caret${isOpen ? ' open' : ''}`}>▸</span>
              <span className="file-icon">📁</span>
              <span className="file-text">{node.name}</span>
              <span className="file-meta">{fileIdsUnder(node).length} 个文件</span>
            </button>
          ) : (
            <button
              className="file-name as-button"
              onClick={() => void startDownload([node.file!.id])}
              disabled={busy}
              title="点击下载这个文件"
            >
              <span className="file-caret" />
              <span className="file-icon">📄</span>
              <span className="file-text">{node.name}</span>
              <span className="file-meta">{formatBytes(node.size ?? 0)}</span>
              <span className="file-dl">下载 ↓</span>
            </button>
          )}
        </div>
        {isFolder && isOpen && node.children.map((c) => renderNode(c, depth + 1))}
      </div>
    );
  };

  return (
    <div className="panel" style={{ marginTop: 18 }}>
      <div className="section-head" style={{ marginBottom: 12 }}>
        <h2>课程文件</h2>
        {stats && (
          <span className="section-note">
            {stats.count} 个文件 · {formatBytes(stats.bytes)}
          </span>
        )}
        <div className="spacer" />
        <button className="btn" onClick={() => void load(true)} disabled={loading || busy} title="重新拉取文件列表">
          刷新
        </button>
        {busy ? (
          <button className="btn btn-ghost" onClick={() => void window.elearning.files.cancel()}>
            取消下载
          </button>
        ) : (
          <button
            className="btn btn-primary"
            onClick={() => void startDownload()}
            disabled={loading || !stats || stats.count === 0}
          >
            下载本课全部
          </button>
        )}
      </div>

      <div className="files-root">
        下载到：<code>{root || '…'}</code>
        <button className="btn btn-ghost" style={{ marginLeft: 8 }} onClick={() => void changeRoot()}>
          更改
        </button>
      </div>

      {progress && (
        <div className="dl-progress">
          <div className="dl-progress-head">
            <span>
              {progress.state === 'done'
                ? '下载完成'
                : progress.state === 'cancelled'
                  ? '已取消'
                  : `正在下载：${progress.currentName || '准备中…'}`}
            </span>
            <span className="num">
              {progress.completed + progress.skipped} / {progress.total}
              {progress.failed > 0 && <span style={{ color: 'var(--bad)' }}> · 失败 {progress.failed}</span>}
            </span>
          </div>
          <div className="progress-track">
            <div
              className="progress-fill"
              style={{ width: `${percent ?? (progress.state === 'done' ? 100 : 4)}%` }}
            />
          </div>
          <div className="dl-progress-foot">
            <span>{formatBytes(progress.bytesReceived)} / {formatBytes(progress.bytesTotal)}</span>
            {progress.skipped > 0 && <span>已跳过 {progress.skipped} 个（本地已存在）</span>}
          </div>
        </div>
      )}

      {result && result.state === 'done' && result.failed === 0 && (
        <div className="alert alert-info" style={{ marginTop: 10 }}>
          已下载 {result.completed} 个文件{result.skipped > 0 ? `，跳过 ${result.skipped} 个已存在的` : ''}。
        </div>
      )}

      {result && result.errors.length > 0 && (
        <div className="alert alert-warn" style={{ marginTop: 10 }}>
          <strong>{result.failed} 个文件下载失败：</strong>
          <ul className="warn-list" style={{ marginTop: 6 }}>
            {result.errors.slice(0, 6).map((e) => (
              <li key={e.relativePath}>
                <code>{e.relativePath}</code> — {e.message}
              </li>
            ))}
            {result.errors.length > 6 && <li>…还有 {result.errors.length - 6} 个</li>}
          </ul>
          <div style={{ marginTop: 6, fontSize: 12.5 }}>
            下载链接有时效，刷新文件列表后重试即可。
          </div>
        </div>
      )}

      {selected.size > 0 && (
        <div className="files-toolbar">
          <span>已选 {selected.size} 个文件</span>
          <button className="btn" onClick={() => setSelected(new Set())} disabled={busy}>
            清空
          </button>
          <button
            className="btn btn-primary"
            onClick={() => void startDownload([...selected])}
            disabled={busy}
          >
            下载选中
          </button>
        </div>
      )}

      {loading && <div className="loading-line">正在读取文件列表…</div>}

      {error && (
        <div className="alert alert-error" style={{ marginTop: 10 }}>
          {error}
        </div>
      )}

      {!loading && !error && tree && tree.children.length === 0 && (
        <div className="empty">这门课还没有上传任何文件。</div>
      )}

      {!loading && tree && tree.children.length > 0 && (
        <div className="file-tree">{tree.children.map((c) => renderNode(c, 0))}</div>
      )}
    </div>
  );
}
