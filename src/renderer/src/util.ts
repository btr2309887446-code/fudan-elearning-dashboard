import type { AssignmentRow, CourseSummary } from '../../core/types';

/** Score bands shared by every view so colours stay consistent (iOS palette). */
export function scoreColor(score: number | null): string {
  if (score === null || Number.isNaN(score)) return 'var(--muted)';
  if (score >= 90) return 'var(--good)';
  if (score >= 80) return 'var(--accent)';
  if (score >= 70) return '#ffb020';
  if (score >= 60) return '#ff9500';
  return 'var(--bad)';
}

export function scoreLabel(score: number | null): string {
  if (score === null || Number.isNaN(score)) return '暂无';
  if (score >= 90) return '优秀';
  if (score >= 80) return '良好';
  if (score >= 70) return '中等';
  if (score >= 60) return '及格';
  return '待提升';
}

export function formatScore(score: number | null, digits = 2): string {
  return score === null || Number.isNaN(score) ? '—' : score.toFixed(digits);
}

export function formatDate(iso: string | null | undefined, withTime = true): string {
  if (!iso) return '—';
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return '—';
  return new Date(t).toLocaleString('zh-CN', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    ...(withTime ? { hour: '2-digit', minute: '2-digit' } : {}),
  });
}

export function relativeDue(iso: string | null | undefined): { text: string; tone: 'overdue' | 'soon' | 'later' | 'none' } {
  if (!iso) return { text: '无截止时间', tone: 'none' };
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return { text: '无截止时间', tone: 'none' };
  const diff = t - Date.now();
  const days = Math.floor(diff / 86_400_000);
  if (diff < 0) return { text: `已逾期 ${Math.abs(days)} 天`, tone: 'overdue' };
  if (diff < 86_400_000) return { text: `今天截止（${Math.max(1, Math.round(diff / 3_600_000))} 小时内）`, tone: 'soon' };
  if (days < 3) return { text: `${days + 1} 天内截止`, tone: 'soon' };
  return { text: `还有 ${days} 天`, tone: 'later' };
}

/**
 * Relative-due wording that never nags about work already handed in.
 *
 * A submission that is past its due date but awaiting grading is *done*: the
 * only thing left is the teacher's marking, so showing "已逾期" there is wrong
 * and just adds noise.
 */
export function dueRelative(
  iso: string | null | undefined,
  done: boolean
): { text: string; tone: 'overdue' | 'soon' | 'later' | 'none' } {
  if (done) return { text: '', tone: 'later' };
  return relativeDue(iso);
}

/** The student's submitted state, independent of whether it has been marked. */
export const WORKFLOW_DONE = new Set(['submitted', 'graded', 'pending_review', 'complete', 'graded_pending']);

export function isCompleted(row: AssignmentRow): boolean {
  if (row.excused) return true;
  if (row.score !== null) return true;
  if (row.submittedAt) return true;
  return WORKFLOW_DONE.has((row.workflowState ?? '').toLowerCase());
}

/** Weighted average across courses that actually have a score. */
export function averageScore(courses: CourseSummary[]): number | null {
  const scored = courses.filter((c) => c.currentScore !== null);
  if (scored.length === 0) return null;
  return scored.reduce((s, c) => s + (c.currentScore as number), 0) / scored.length;
}

export function submissionState(row: AssignmentRow): { label: string; cls: string } {
  if (row.excused) return { label: '已免除', cls: 'tag-neutral' };
  if (row.score !== null) return { label: row.late ? '已评分（迟交）' : '已评分', cls: row.late ? 'tag-warn' : 'tag-good' };
  // Checked before `missing` on purpose: a handed-in paper is never "缺交",
  // whatever Canvas chose to put in that flag.
  if (isCompleted(row)) {
    return { label: row.late ? '已提交（迟交）待评分' : '已提交待评分', cls: row.late ? 'tag-warn' : 'tag-info' };
  }
  if (row.missing) return { label: '未提交', cls: 'tag-bad' };
  const due = row.dueAt ? Date.parse(row.dueAt) : NaN;
  if (!Number.isNaN(due) && due < Date.now()) return { label: '已逾期未交', cls: 'tag-bad' };
  return { label: '未开始', cls: 'tag-neutral' };
}

/** Sort courses so the ones with the most attention needed surface first. */
export function courseUrgency(a: CourseSummary, b: CourseSummary): number {
  const missDiff = b.missingCount - a.missingCount;
  if (missDiff !== 0) return missDiff;
  const sa = a.currentScore ?? 101;
  const sb = b.currentScore ?? 101;
  if (sa !== sb) return sa - sb;
  return a.displayName.localeCompare(b.displayName, 'zh-Hans-CN');
}

export function clampPercent(v: number | null): number {
  if (v === null || Number.isNaN(v)) return 0;
  return Math.max(0, Math.min(100, v));
}
