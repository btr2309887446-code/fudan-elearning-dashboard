import { useMemo, useState } from 'react';
import { filterIgnored, toIgnoredSet } from '../../../core/ignored';
import type { AssignmentRow, Snapshot } from '../../../core/types';
import { dueRelative, formatDate, isCompleted } from '../util';
import type { TermFilter } from '../types';

interface Props {
  snapshot: Snapshot;
  termFilter: TermFilter;
  hideUnsubmitted: boolean;
  /** 手动标记为「无需提交」的作业键；不进时间线。 */
  ignoredKeys: string[];
  onSelectCourse: (id: number) => void;
  /** 点「详情」时把原始作业行交出去，由 App 打开浮层。 */
  onOpenAssignment: (row: AssignmentRow) => void;
}

interface Item {
  key: string;
  title: string;
  courseId: number | null;
  courseName: string;
  dueAt: string | null;
  pointsPossible: number | null;
  htmlUrl?: string;
  kind: string;
  /** Handed in - graded or merely awaiting marking. */
  done: boolean;
  state: 'graded' | 'submitted' | 'missing' | 'open';
  /** 来自作业列表的条目才带原始行；来自 Canvas todo 的没有详情可看。 */
  row?: AssignmentRow;
}

export default function Timeline({
  snapshot,
  termFilter,
  hideUnsubmitted,
  ignoredKeys,
  onSelectCourse,
  onOpenAssignment,
}: Props) {
  const [showCompleted, setShowCompleted] = useState(false);
  // 标记为「无需提交」的不进时间线——它们永远不会有截止动作。
  const ignoredSet = useMemo(() => toIgnoredSet(ignoredKeys), [ignoredKeys]);

  const items = useMemo<Item[]>(() => {
    // Scope to the selected semester before doing anything else.
    const courses =
      termFilter === 'all' ? snapshot.courses : snapshot.courses.filter((c) => c.termId === termFilter);
    const ids = new Set(courses.map((c) => c.id));
    const scoped = filterIgnored(
      snapshot.assignments.filter((a) => ids.has(a.courseId)),
      ignoredSet
    );
    const scopedTodo = snapshot.todo.filter((t) => t.courseId === null || ids.has(t.courseId));

    const byAssignment = new Map<number, Item>();

    for (const a of scoped) {
      const done = isCompleted(a);
      const state: Item['state'] = a.score !== null ? 'graded' : done ? 'submitted' : a.missing ? 'missing' : 'open';
      byAssignment.set(a.id, {
        key: `a-${a.courseId}-${a.id}`,
        title: a.name,
        courseId: a.courseId,
        courseName: a.courseName,
        dueAt: a.dueAt,
        pointsPossible: a.pointsPossible,
        htmlUrl: a.htmlUrl,
        kind: a.groupName,
        done,
        state,
        row: a,
      });
    }

    // Canvas' own todo list wins for anything it knows about, since it reflects
    // the server's view of what is still outstanding.
    for (const t of scopedTodo) {
      const existing = [...byAssignment.values()].find(
        (i) => i.title === t.title && (t.courseId === null || i.courseId === t.courseId)
      );
      if (existing) {
        existing.dueAt = t.dueAt ?? existing.dueAt;
        continue;
      }
      byAssignment.set(-Math.abs(t.title.length + (t.courseId ?? 0)), {
        key: `t-${t.courseId}-${t.title}`,
        title: t.title,
        courseId: t.courseId,
        courseName: t.courseName,
        dueAt: t.dueAt,
        pointsPossible: t.pointsPossible,
        htmlUrl: t.htmlUrl,
        kind: t.kind === 'quiz' ? '测验' : '待办',
        done: false,
        state: 'open',
      });
    }

    return [...byAssignment.values()].sort((a, b) => {
      const ta = a.dueAt ? Date.parse(a.dueAt) : Number.MAX_SAFE_INTEGER;
      const tb = b.dueAt ? Date.parse(b.dueAt) : Number.MAX_SAFE_INTEGER;
      return ta - tb;
    });
  }, [snapshot, termFilter, ignoredSet]);

  const now = Date.now();
  // While ignoring unsubmitted work, finished items are the whole point of the
  // list, so the "show completed" switch stops applying.
  const withCompleted = showCompleted || hideUnsubmitted;
  const pool = hideUnsubmitted ? items.filter((i) => i.done) : items;

  const open = pool.filter((i) => !i.done);
  const buckets = [
    { title: '已逾期未交', items: open.filter((i) => i.dueAt && Date.parse(i.dueAt) < now) },
    {
      title: '三天内截止',
      items: open.filter((i) => i.dueAt && Date.parse(i.dueAt) >= now && Date.parse(i.dueAt) - now < 3 * 86_400_000),
    },
    { title: '之后', items: open.filter((i) => i.dueAt && Date.parse(i.dueAt) - now >= 3 * 86_400_000) },
    { title: '无截止时间', items: open.filter((i) => !i.dueAt) },
    { title: '已完成', items: withCompleted ? pool.filter((i) => i.done) : [] },
  ].filter((b) => b.items.length > 0);

  const totalOpen = items.filter((i) => !i.done).length;
  const totalDone = items.filter((i) => i.done).length;

  return (
    <>
      <div className="section-head">
        <h2>作业与截止时间</h2>
        <small style={{ color: 'var(--muted)' }}>
          {hideUnsubmitted
            ? `已忽略未提交 · 显示 ${totalDone} 项已完成`
            : `待处理 ${totalOpen} 项 · 已完成 ${totalDone} 项`}
        </small>
        <div className="spacer" />
        {hideUnsubmitted ? (
          <span className="section-note">正在忽略未提交的作业</span>
        ) : (
          <label className="checkbox" style={{ marginBottom: 0 }}>
            <input type="checkbox" checked={showCompleted} onChange={(e) => setShowCompleted(e.target.checked)} />
            显示已完成
          </label>
        )}
      </div>

      {buckets.length === 0 && (
        <div className="empty">
          {hideUnsubmitted ? '这个范围内没有已提交的作业。' : '没有待办事项，暂时轻松。'}
        </div>
      )}

      {buckets.map((bucket) => (
        <div key={bucket.title} style={{ marginBottom: 22 }}>
          <div style={{ fontSize: 13, color: 'var(--text-dim)', margin: '0 0 9px', fontWeight: 560 }}>
            {bucket.title}
            <span style={{ color: 'var(--muted)', fontWeight: 400 }}> · {bucket.items.length} 项</span>
          </div>
          <div className="timeline">
            {bucket.items.map((i) => {
              const rel = dueRelative(i.dueAt, i.done);
              return (
                <div key={i.key} className={`tl-item tone-${rel.tone}`}>
                  <div className="tl-due">{formatDate(i.dueAt)}</div>
                  <div className="tl-main">
                    <div className="tl-title">{i.title}</div>
                    <div className="tl-sub">
                      {i.courseName}
                      {i.pointsPossible !== null ? ` · 满分 ${i.pointsPossible}` : ''}
                      {i.kind ? ` · ${i.kind}` : ''}
                    </div>
                  </div>
                  <div className="tl-rel" style={{ marginRight: 10 }}>
                    {i.state === 'graded' ? (
                      <span className="tag tag-good">已评分</span>
                    ) : i.state === 'submitted' ? (
                      <span className="tag tag-info">已提交待评分</span>
                    ) : i.state === 'missing' ? (
                      <span className="tag tag-bad">未提交</span>
                    ) : (
                      <span style={{ color: rel.tone === 'overdue' ? 'var(--bad)' : 'var(--text-dim)' }}>
                        {rel.text}
                      </span>
                    )}
                  </div>
                  <div style={{ display: 'flex', gap: 6 }}>
                    {i.courseId !== null && (
                      <button
                        className="btn btn-ghost"
                        style={{ padding: '4px 9px', fontSize: 12 }}
                        onClick={() => onSelectCourse(i.courseId as number)}
                      >
                        课程
                      </button>
                    )}
                    {i.row ? (
                      <button
                        className="btn btn-ghost"
                        style={{ padding: '4px 9px', fontSize: 12 }}
                        onClick={() => onOpenAssignment(i.row as AssignmentRow)}
                        title="查看作业详情与简介"
                      >
                        详情
                      </button>
                    ) : (
                      i.htmlUrl && (
                        <button
                          className="btn btn-ghost"
                          style={{ padding: '4px 9px', fontSize: 12 }}
                          onClick={() => window.elearning.open(i.htmlUrl as string)}
                          title="这条来自 Canvas 待办，没有本地详情"
                        >
                          网页
                        </button>
                      )
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      ))}
    </>
  );
}
