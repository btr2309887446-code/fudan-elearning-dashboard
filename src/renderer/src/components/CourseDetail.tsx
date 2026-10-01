import { useMemo, useState } from 'react';
import { isIgnored, toIgnoredSet } from '../../../core/ignored';
import { buildCourseDetail } from '../../../core/scoring';
import type { AssignmentRow, Snapshot } from '../../../core/types';
import {
  dueRelative,
  formatDate,
  formatScore,
  isCompleted,
  scoreColor,
  scoreLabel,
  submissionState,
} from '../util';
import ScoreRing from './ScoreRing';
import CourseFiles from './CourseFiles';
import { GroupChart, ScoreTrendChart } from './charts';

interface Props {
  snapshot: Snapshot;
  courseId: number;
  hideUnsubmitted: boolean;
  /** 手动标记为「无需提交」的作业键；这些不计入本页的缺交数。 */
  ignoredKeys: string[];
  onBack: () => void;
  onOpenAssignment: (row: AssignmentRow) => void;
}

type SortKey = 'due' | 'score' | 'group';

export default function CourseDetail({
  snapshot,
  courseId,
  hideUnsubmitted,
  ignoredKeys,
  onBack,
  onOpenAssignment,
}: Props) {
  const detail = useMemo(() => buildCourseDetail(snapshot, courseId), [snapshot, courseId]);
  const ignoredSet = useMemo(() => toIgnoredSet(ignoredKeys), [ignoredKeys]);
  const [sort, setSort] = useState<SortKey>('due');
  const [onlyUnfinished, setOnlyUnfinished] = useState(false);

  if (!detail) {
    return (
      <>
        <button className="back-link" onClick={onBack}>
          ← 返回总览
        </button>
        <div className="empty">找不到该课程。</div>
      </>
    );
  }
  const { course, groups, assignments } = detail;

  // 被标记为「无需提交」的不算缺交。这里现算，而不是直接用主进程给的
  // course.missingCount——后者不知道用户在本机标了什么。
  const missingCount = assignments.filter(
    (r) => r.missing && !isIgnored(ignoredSet, r.courseId, r.id)
  ).length;
  const ignoredCount = assignments.filter((r) => isIgnored(ignoredSet, r.courseId, r.id)).length;

  let rows = [...assignments];
  if (hideUnsubmitted) rows = rows.filter((r) => isCompleted(r));
  if (onlyUnfinished) rows = rows.filter((r) => r.score === null && !r.excused);
  rows.sort((a, b) => {
    if (sort === 'score') {
      const sa = a.percent ?? -1;
      const sb = b.percent ?? -1;
      return sa - sb;
    }
    if (sort === 'group') return a.groupName.localeCompare(b.groupName, 'zh-Hans-CN') || a.name.localeCompare(b.name, 'zh-Hans-CN');
    const ta = a.dueAt ? Date.parse(a.dueAt) : Number.MAX_SAFE_INTEGER;
    const tb = b.dueAt ? Date.parse(b.dueAt) : Number.MAX_SAFE_INTEGER;
    return ta - tb;
  });

  return (
    <>
      <div className="panel" style={{ marginBottom: 16 }}>
        <div style={{ display: 'flex', gap: 22, alignItems: 'center', flexWrap: 'wrap' }}>
          <ScoreRing score={course.currentScore} size={104} stroke={9} />
          <div style={{ flex: 1, minWidth: 240 }}>
            <h2 style={{ margin: '0 0 4px', fontSize: 19, fontWeight: 660 }}>{course.displayName}</h2>
            <div style={{ color: 'var(--muted)', fontSize: 12.5, marginBottom: 12 }}>{course.courseCode}</div>
            <div className="course-foot">
              <span className="chip">{course.termName}</span>
              <span className="chip" style={{ color: scoreColor(course.currentScore) }}>
                {scoreLabel(course.currentScore)}
              </span>
              {course.currentGrade && <span className="chip">等级 {course.currentGrade}</span>}
              {course.finalScore !== null && <span className="chip">最终分 {formatScore(course.finalScore)}</span>}
              <span className="chip">{detail.gradingScheme === 'weighted' ? '按权重计分' : '按总分计分'}</span>
              <span className="chip">共 {course.assignmentCount} 项</span>
              {missingCount > 0 && <span className="chip chip-bad">缺交 {missingCount}</span>}
              {ignoredCount > 0 && <span className="chip">已标记无需提交 {ignoredCount}</span>}
              {course.lateCount > 0 && <span className="chip chip-warn">迟交 {course.lateCount}</span>}
            </div>
          </div>
          <div style={{ display: 'flex', gap: 26, textAlign: 'right' }}>
            <div>
              <div className="stat-label">已得 / 已评总分</div>
              <div className="stat-value" style={{ fontSize: 21 }}>
                {course.earnedPoints !== null && course.possiblePointsGraded !== null
                  ? `${course.earnedPoints.toFixed(1)} / ${course.possiblePointsGraded.toFixed(0)}`
                  : '—'}
              </div>
            </div>
            <div>
              <div className="stat-label">已评分项</div>
              <div className="stat-value" style={{ fontSize: 21 }}>
                {course.gradedCount}
                <span className="stat-unit">/ {course.assignmentCount}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="two-col" style={{ marginBottom: 18 }}>
        <div className="panel">
          <h3 className="panel-title">
            得分趋势 <small>按截止时间累计的课程百分比</small>
          </h3>
          <ScoreTrendChart rows={assignments} />
        </div>
        <div className="panel">
          <h3 className="panel-title">
            作业分组达成度 <small>括号内为该项权重</small>
          </h3>
          <GroupChart groups={groups} />
          <div className="group-list" style={{ marginTop: 14 }}>
            {groups.map((g) => (
              <div key={g.id}>
                <div className="group-row-head">
                  <span className="g-name">
                    {g.name}
                    {g.weight > 0 ? `（${g.weight}%）` : ''}
                  </span>
                  <span className="g-val">
                    {g.percent !== null ? `${g.percent.toFixed(1)}%` : '未评分'}
                    {g.possible > 0 ? ` · ${g.earned.toFixed(1)}/${g.possible.toFixed(0)}` : ''}
                  </span>
                </div>
                <div className="progress-track">
                  <div
                    className="progress-fill"
                    style={{
                      width: `${Math.max(0, Math.min(100, g.percent ?? 0))}%`,
                      background: scoreColor(g.percent),
                    }}
                  />
                </div>
              </div>
            ))}
            {groups.length === 0 && <div className="empty">暂无分组数据</div>}
          </div>
        </div>
      </div>

      <div className="section-head">
        <h2>作业明细</h2>
        <small style={{ color: 'var(--muted)' }}>
          显示 {rows.length} / {assignments.length} 项
        </small>
        <div className="spacer" />
        {hideUnsubmitted ? (
          <span className="section-note">正在忽略未提交的作业</span>
        ) : (
          <label className="checkbox" style={{ marginBottom: 0 }}>
            <input type="checkbox" checked={onlyUnfinished} onChange={(e) => setOnlyUnfinished(e.target.checked)} />
            只看未完成
          </label>
        )}
        <select
          value={sort}
          onChange={(e) => setSort(e.target.value as SortKey)}
          className="btn"
          style={{ padding: '6px 10px' }}
        >
          <option value="due">按截止时间</option>
          <option value="score">按得分率（低→高）</option>
          <option value="group">按作业分组</option>
        </select>
      </div>

      <div className="table-wrap">
        <table className="data">
          <thead>
            <tr>
              <th style={{ minWidth: 220 }}>作业</th>
              <th>分组</th>
              <th className="num">得分</th>
              <th className="num">满分</th>
              <th style={{ minWidth: 140 }}>得分率</th>
              <th>截止时间</th>
              <th>状态</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const state = submissionState(r);
              const done = isCompleted(r);
              const rel = dueRelative(r.dueAt, done);
              return (
                <tr key={r.id}>
                  <td>
                    <div style={{ fontWeight: 520 }}>{r.name}</div>
                    {r.omitFromFinalGrade && (
                      <div style={{ fontSize: 11, color: 'var(--muted)' }}>不计入总评</div>
                    )}
                  </td>
                  <td style={{ color: 'var(--text-dim)', fontSize: 12 }}>{r.groupName}</td>
                  <td className="num" style={{ color: scoreColor(r.percent), fontWeight: 560 }}>
                    {r.score !== null ? formatScore(r.score) : '—'}
                  </td>
                  <td className="num" style={{ color: 'var(--text-dim)' }}>
                    {r.pointsPossible ?? '—'}
                  </td>
                  <td>
                    {r.percent !== null ? (
                      <div className="bar-mini">
                        <div className="bar-mini-track">
                          <div
                            className="bar-mini-fill"
                            style={{
                              width: `${Math.max(0, Math.min(100, r.percent))}%`,
                              background: scoreColor(r.percent),
                            }}
                          />
                        </div>
                        <span className="num" style={{ fontSize: 12, color: 'var(--text-dim)' }}>
                          {r.percent.toFixed(0)}%
                        </span>
                      </div>
                    ) : (
                      <span style={{ color: 'var(--muted)' }}>—</span>
                    )}
                  </td>
                  <td className="num" style={{ fontSize: 12, color: 'var(--text-dim)' }}>
                    {formatDate(r.dueAt)}
                    {rel.tone === 'overdue' && (
                      <div style={{ color: 'var(--bad)', fontSize: 11 }}>{rel.text}</div>
                    )}
                  </td>
                  <td>
                    <span className={`tag ${state.cls}`}>{state.label}</span>
                  </td>
                  <td>
                    {/* 详情在应用内看，不再直接把人赶去浏览器 */}
                    <button
                      className="btn btn-ghost"
                      style={{ padding: '4px 9px', fontSize: 12 }}
                      onClick={() => onOpenAssignment(r)}
                      title="查看作业详情与简介"
                    >
                      详情
                    </button>
                  </td>
                </tr>
              );
            })}
            {rows.length === 0 && (
              <tr>
                <td colSpan={8}>
                  <div className="empty">没有符合条件的作业。</div>
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <CourseFiles courseId={courseId} />
    </>
  );
}
