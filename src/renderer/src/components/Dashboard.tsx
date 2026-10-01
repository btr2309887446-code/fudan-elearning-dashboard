import { useMemo } from 'react';
import type { AssignmentRow, Snapshot } from '../../../core/types';
import type { TermFilter } from '../types';
import {
  averageScore,
  courseUrgency,
  dueRelative,
  formatDate,
  formatScore,
  isCompleted,
  scoreColor,
  scoreLabel,
} from '../util';
import Icon, { type IconName } from './Icon';
import ScoreRing from './ScoreRing';
import { CourseScoreChart } from './charts';

/** 首页板块。顺序即默认显示顺序；key 存进偏好里，改动要保持兼容。 */
export const SECTIONS: { key: string; label: string; icon: IconName }[] = [
  { key: 'stats', label: '数据概览', icon: 'chart' },
  { key: 'unsubmitted', label: '未提交作业', icon: 'inbox' },
  { key: 'soon', label: '三天内截止', icon: 'clock' },
  { key: 'charts', label: '得分与关注', icon: 'target' },
  { key: 'courses', label: '课程卡片', icon: 'book' },
  { key: 'warnings', label: '数据警告', icon: 'alert' },
];

interface Props {
  snapshot: Snapshot;
  termFilter: TermFilter;
  hideUnsubmitted: boolean;
  /** 板块开关；缺省视为显示，新增板块老用户也能看到。 */
  sections: Record<string, boolean>;
  onToggleSection: (key: string) => void;
  onOpenAssignment: (row: AssignmentRow) => void;
  onSelectCourse: (id: number) => void;
  /** 用户排定的板块顺序（section key 列表）。 */
  sectionOrder: string[];
  onMoveSection: (key: string, direction: -1 | 1) => void;
  onResetOrder: () => void;
}

export default function Dashboard({
  snapshot,
  termFilter,
  hideUnsubmitted,
  sections,
  onToggleSection,
  onOpenAssignment,
  onSelectCourse,
  sectionOrder,
  onMoveSection,
  onResetOrder,
}: Props) {
  /**
   * 按用户排的顺序整理板块。
   *
   * 不认识的 key 忽略；顺序里没提到的板块按默认顺序补在后面——
   * 这样以后新增板块时，老用户的顺序表不会把它漏掉。
   */
  const orderedSections = useMemo(() => {
    const known = new Map(SECTIONS.map((s) => [s.key, s]));
    const out: typeof SECTIONS = [];
    for (const k of sectionOrder) {
      const s = known.get(k);
      if (s && !out.includes(s)) out.push(s);
    }
    for (const s of SECTIONS) if (!out.includes(s)) out.push(s);
    return out;
  }, [sectionOrder]);

  /**
   * 板块的显示序号。
   *
   * 用 CSS 的 `order` 在 flex 容器里重排，而不是把 JSX 拆成一堆回调——
   * 板块内容长且各带条件渲染，拆开只会让这段代码难读。
   */
  const ord = (key: string) => {
    const i = orderedSections.findIndex((s) => s.key === key);
    return i < 0 ? 100 : i;
  };

  // Everything on this page is scoped to the selected semester: averaging
  // scores across semesters would not mean anything.
  const view = useMemo(() => {
    const courses =
      termFilter === 'all'
        ? snapshot.courses
        : snapshot.courses.filter((c) => c.termId === termFilter);
    const ids = new Set(courses.map((c) => c.id));
    return {
      courses,
      assignments: snapshot.assignments.filter((a) => ids.has(a.courseId)),
      todo: snapshot.todo.filter((t) => t.courseId === null || ids.has(t.courseId)),
    };
  }, [snapshot, termFilter]);

  const avg = averageScore(view.courses);
  // Unsubmitted work is what the "缺交" figure is made of, so ignoring it has
  // to zero the counter too.
  const missing = hideUnsubmitted ? 0 : view.courses.reduce((s, c) => s + c.missingCount, 0);
  const late = view.courses.reduce((s, c) => s + c.lateCount, 0);
  const graded = view.courses.filter((c) => c.currentScore !== null).length;
  const upcoming = hideUnsubmitted ? 0 : view.todo.length;

  // Anything due in the next three days deserves to be surfaced on the front
  // page - unless it has already been handed in.
  const soon = hideUnsubmitted
    ? []
    : view.assignments
        .filter((a) => !isCompleted(a))
        .filter((a) => a.dueAt && Date.parse(a.dueAt) > Date.now())
        .filter((a) => Date.parse(a.dueAt as string) - Date.now() < 3 * 86_400_000)
        .sort((a, b) => Date.parse(a.dueAt as string) - Date.parse(b.dueAt as string));

  /**
   * 所有还没交的作业，逾期的排前面。
   *
   * 这是「我想看有哪些作业没交」的直接答案：以前只能在课程页里翻，
   * 首页只有一个总数，看不出具体是哪些。
   */
  const unsubmitted = useMemo(() => {
    if (hideUnsubmitted) return { overdue: [] as AssignmentRow[], pending: [] as AssignmentRow[] };
    const open = view.assignments.filter((a) => !isCompleted(a));
    const now = Date.now();
    const overdue: AssignmentRow[] = [];
    const pending: AssignmentRow[] = [];
    for (const a of open) {
      if (a.dueAt && Date.parse(a.dueAt) < now) overdue.push(a);
      else pending.push(a);
    }
    const byDue = (x: AssignmentRow, y: AssignmentRow) => {
      if (!x.dueAt) return 1;
      if (!y.dueAt) return -1;
      return Date.parse(x.dueAt) - Date.parse(y.dueAt);
    };
    overdue.sort(byDue);
    pending.sort(byDue);
    return { overdue, pending };
  }, [view.assignments, hideUnsubmitted]);

  const ranked = [...view.courses].sort(courseUrgency);

  const show = (key: string) => sections[key] !== false;

  if (view.courses.length === 0) {
    return <div className="empty">这个学期没有课程数据。</div>;
  }

  const totalOpen = unsubmitted.overdue.length + unsubmitted.pending.length;

  return (
    <div className="dash-body">
      {/* 板块开关与排序：放在最上面，随时可调 */}
      <div className="dash-customise">
        <span className="dash-customise-label">
          <Icon name="sliders" size={15} />
          首页板块
        </span>
        {orderedSections.map((s, i) => (
          <span key={s.key} className={`dash-toggle ${show(s.key) ? 'on' : ''}`}>
            <button
              className="dash-toggle-main"
              onClick={() => onToggleSection(s.key)}
              title={show(s.key) ? '点击隐藏这个板块' : '点击显示这个板块'}
            >
              <Icon name={s.icon} size={13} />
              {s.label}
            </button>
            {/* 排序：用 CSS order 重排，不动 JSX 结构 */}
            <button
              className="dash-move"
              onClick={() => onMoveSection(s.key, -1)}
              disabled={i === 0}
              title="上移"
            >
              ▲
            </button>
            <button
              className="dash-move"
              onClick={() => onMoveSection(s.key, 1)}
              disabled={i === orderedSections.length - 1}
              title="下移"
            >
              ▼
            </button>
          </span>
        ))}
        <button
          className="dash-toggle dash-reset"
          onClick={onResetOrder}
          title="恢复默认顺序"
        >
          恢复默认
        </button>
      </div>

      {show('stats') && (
        <div className="stat-grid" style={{ order: ord('stats') }}>
          <div className="stat">
            <div className="stat-icon">
              <Icon name="chart" size={19} />
            </div>
            <div className="stat-body">
              <div className="stat-label">当前平均分</div>
              <div className="stat-value" style={{ color: avg !== null ? scoreColor(avg) : undefined }}>
                {formatScore(avg)}
                <span className="stat-unit">分</span>
              </div>
              <div className="stat-hint">
                {termFilter === 'all' ? '跨全部学期' : '仅本学期'} · {graded} 门已有得分
              </div>
            </div>
          </div>

          <div className="stat">
            <div className="stat-icon">
              <Icon name="book" size={19} />
            </div>
            <div className="stat-body">
              <div className="stat-label">课程</div>
              <div className="stat-value">
                {view.courses.length}
                <span className="stat-unit">门</span>
              </div>
              <div className="stat-hint">共 {view.assignments.length} 项作业 / 任务</div>
            </div>
          </div>

          <div className="stat">
            <div className={`stat-icon ${!hideUnsubmitted && missing > 0 ? 'tone-bad' : 'tone-good'}`}>
              <Icon name={!hideUnsubmitted && missing > 0 ? 'alert' : 'check'} size={19} />
            </div>
            <div className="stat-body">
              <div className="stat-label">缺交作业</div>
              <div
                className="stat-value"
                style={{ color: !hideUnsubmitted && missing > 0 ? 'var(--bad)' : undefined }}
              >
                {hideUnsubmitted ? '—' : missing}
                {!hideUnsubmitted && <span className="stat-unit">项</span>}
              </div>
              <div className="stat-hint">
                {hideUnsubmitted
                  ? '已忽略未提交的作业'
                  : missing > 0
                    ? late > 0
                      ? `另有 ${late} 项迟交`
                      : '建议优先处理'
                    : '保持得不错'}
              </div>
            </div>
          </div>

          <div className="stat">
            <div className={`stat-icon ${!hideUnsubmitted && totalOpen > 0 ? 'tone-warn' : ''}`}>
              <Icon name="inbox" size={19} />
            </div>
            <div className="stat-body">
              <div className="stat-label">还没交</div>
              <div className="stat-value" style={{ color: !hideUnsubmitted && totalOpen > 0 ? 'var(--warn)' : undefined }}>
                {hideUnsubmitted ? '—' : totalOpen}
                {!hideUnsubmitted && <span className="stat-unit">项</span>}
              </div>
              <div className="stat-hint">
                {hideUnsubmitted
                  ? '已忽略未提交的作业'
                  : totalOpen > 0
                    ? `${unsubmitted.overdue.length} 项已逾期 · ${unsubmitted.pending.length} 项未到期`
                    : '暂无待交作业'}
              </div>
            </div>
          </div>
        </div>
      )}

      {show('unsubmitted') && !hideUnsubmitted && totalOpen > 0 && (
        <div className="panel" style={{ marginBottom: 18, order: ord('unsubmitted') }}>
          <h3 className="panel-title">
            <Icon name="inbox" size={17} style={{ color: 'var(--warn)' }} />
            未提交的作业
            <small>点任意一条看详情</small>
          </h3>

          {unsubmitted.overdue.length > 0 && (
            <div className="todo-group">
              <div className="todo-group-title" style={{ color: 'var(--bad)' }}>
                <Icon name="alert" size={14} />
                已逾期 {unsubmitted.overdue.length} 项
              </div>
              <div className="timeline">
                {unsubmitted.overdue.map((a) => (
                  <AssignmentLine key={`${a.courseId}-${a.id}`} row={a} onOpen={onOpenAssignment} />
                ))}
              </div>
            </div>
          )}

          {unsubmitted.pending.length > 0 && (
            <div className="todo-group">
              <div className="todo-group-title" style={{ color: 'var(--text-dim)' }}>
                <Icon name="clock" size={14} />
                尚未到期 {unsubmitted.pending.length} 项
              </div>
              <div className="timeline">
                {unsubmitted.pending.map((a) => (
                  <AssignmentLine key={`${a.courseId}-${a.id}`} row={a} onOpen={onOpenAssignment} />
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {show('soon') && soon.length > 0 && (
        <div className="panel" style={{ marginBottom: 18, order: ord('soon') }}>
          <h3 className="panel-title">
            <Icon name="clock" size={17} style={{ color: 'var(--warn)' }} />
            三天内截止
            <small>{soon.length} 项</small>
          </h3>
          <div className="timeline">
            {soon.map((a) => (
              <AssignmentLine key={`${a.courseId}-${a.id}`} row={a} onOpen={onOpenAssignment} />
            ))}
          </div>
        </div>
      )}

      {show('charts') && (
        <div className="two-col" style={{ marginBottom: 18, order: ord('charts') }}>
          <div className="panel">
            <h3 className="panel-title">
              <Icon name="chart" size={17} style={{ color: 'var(--accent)' }} />
              各课程当前得分
              <small>点击柱子进入课程详情</small>
            </h3>
            <CourseScoreChart courses={view.courses} onSelect={onSelectCourse} />
          </div>

          <div className="panel">
            <h3 className="panel-title">
              <Icon name="target" size={17} style={{ color: 'var(--bad)' }} />
              需要关注
              <small>按缺交与得分排序</small>
            </h3>
            <div className="group-list">
              {ranked.slice(0, 6).map((c) => (
                <button key={c.id} className="mini-card" onClick={() => onSelectCourse(c.id)}>
                  <ScoreRing score={c.currentScore} size={42} stroke={4.5} showLabel={false} />
                  <div className="mini-body">
                    <div className="mini-title">{c.displayName}</div>
                    <div className="mini-sub">
                      {!hideUnsubmitted && c.missingCount > 0 ? `缺交 ${c.missingCount} 项 · ` : ''}
                      {c.currentScore !== null ? scoreLabel(c.currentScore) : '暂无得分'}
                      {c.assignmentCount > 0 ? ` · 共 ${c.assignmentCount} 项作业` : ''}
                    </div>
                  </div>
                  <Icon name="back" size={16} style={{ transform: 'rotate(180deg)', color: 'var(--muted)' }} />
                </button>
              ))}
              {ranked.length === 0 && <div className="empty">暂无课程数据</div>}
            </div>
          </div>
        </div>
      )}

      {show('courses') && (
        <div style={{ order: ord('courses') }}>
          <div className="section-head">
            <h2>课程</h2>
            <small style={{ color: 'var(--muted)' }}>{view.courses.length} 门</small>
          </div>

          <div className="course-grid">
            {view.courses.map((c) => (
              <button key={c.id} className="course-card" onClick={() => onSelectCourse(c.id)}>
                <div className="course-head">
                  <ScoreRing score={c.currentScore} size={66} stroke={6.5} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div className="course-name">{c.displayName}</div>
                    <div className="course-code">{c.courseCode}</div>
                  </div>
                </div>

                <div>
                  <div className="group-row-head" style={{ marginBottom: 5 }}>
                    <span className="g-name" style={{ fontSize: 11.5, color: 'var(--muted)' }}>
                      得分构成
                    </span>
                    <span className="g-val" style={{ fontSize: 11.5 }}>
                      {c.earnedPoints !== null && c.possiblePointsGraded !== null
                        ? `${c.earnedPoints.toFixed(1)} / ${c.possiblePointsGraded.toFixed(0)} 分`
                        : '尚无评分'}
                    </span>
                  </div>
                  <div className="progress-track">
                    <div
                      className="progress-fill"
                      style={{
                        width: `${Math.max(0, Math.min(100, c.currentScore ?? 0))}%`,
                        background: scoreColor(c.currentScore),
                      }}
                    />
                  </div>
                </div>

                <div className="course-foot">
                  {termFilter === 'all' && <span className="chip">{c.termName}</span>}
                  <span className="chip">{c.assignmentCount} 项作业</span>
                  {c.gradedCount > 0 && <span className="chip">已评分 {c.gradedCount}</span>}
                  {!hideUnsubmitted && c.missingCount > 0 && (
                    <span className="chip chip-bad">缺交 {c.missingCount}</span>
                  )}
                  {!hideUnsubmitted && c.lateCount > 0 && (
                    <span className="chip chip-warn">迟交 {c.lateCount}</span>
                  )}
                  {!hideUnsubmitted && c.missingCount === 0 && c.lateCount === 0 && c.assignmentCount > 0 && (
                    <span className="chip">全部按时</span>
                  )}
                </div>
              </button>
            ))}
          </div>
        </div>
      )}

      {show('warnings') && snapshot.warnings.length > 0 && (
        <div className="panel" style={{ marginTop: 18, order: ord('warnings') }}>
          <h3 className="panel-title">
            <Icon name="alert" size={17} style={{ color: 'var(--warn)' }} />
            部分数据未能获取
            <small>{snapshot.warnings.length} 条</small>
          </h3>
          <ul className="warn-list">
            {snapshot.warnings.slice(0, 12).map((w, i) => (
              <li key={i}>{w}</li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

/** 一行作业：点开详情，而不是跳浏览器。 */
function AssignmentLine({ row, onOpen }: { row: AssignmentRow; onOpen: (r: AssignmentRow) => void }) {
  const rel = dueRelative(row.dueAt, false);
  const overdue = rel.tone === 'overdue';
  return (
    <button
      className={`tl-item as-button tone-${rel.tone}`}
      onClick={() => onOpen(row)}
      title="查看作业详情与简介"
    >
      <div className="tl-due">{formatDate(row.dueAt)}</div>
      <div className="tl-main">
        <div className="tl-title">{row.name}</div>
        <div className="tl-sub">
          {row.courseName}
          {row.pointsPossible !== null ? ` · 满分 ${row.pointsPossible}` : ''}
        </div>
      </div>
      <div
        className="tl-rel"
        style={{
          color: overdue ? 'var(--bad)' : rel.tone === 'soon' ? 'var(--warn)' : 'var(--muted)',
          fontWeight: 550,
        }}
      >
        {rel.text || '无截止时间'}
      </div>
    </button>
  );
}
