/**
 * Pure grade arithmetic.
 *
 * Deliberately free of any Node or network imports so the renderer can reuse it
 * directly; the CLI/Electron side imports it through `aggregate.ts`.
 *
 * Score handling deserves a note. Canvas exposes a server-computed
 * `computed_current_score`, but it can be null while work is ungraded, and it
 * does not always reflect assignment-group weighting. We therefore recompute
 * the score locally from submissions and reconcile the two: the local number
 * drives the per-group breakdown, while the server number wins for display
 * whenever it exists.
 */

import type {
  AssignmentRow,
  CanvasAssignment,
  CanvasCourse,
  CanvasEnrollment,
  CanvasGrades,
  CanvasProfile,
  CanvasTerm,
  CourseDetail,
  CourseSummary,
  Snapshot,
  TermGroup,
} from './types.ts';
import { makeExcerpt } from './summary.ts';

export function num(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

/** Pick the signed-in student's own enrollment out of a course. */
export function pickOwnEnrollment(course: CanvasCourse): CanvasEnrollment | null {
  const list = course.enrollments ?? [];
  if (list.length === 0) return null;
  return (
    list.find((e) => e.type === 'StudentEnrollment' || e.role === 'StudentEnrollment') ?? list[0]
  );
}

export interface ExtractedScores {
  currentScore: number | null;
  finalScore: number | null;
  currentGrade: string | null;
  finalGrade: string | null;
}

export function extractScores(enrollment: CanvasEnrollment | null): ExtractedScores {
  if (!enrollment) {
    return { currentScore: null, finalScore: null, currentGrade: null, finalGrade: null };
  }
  const g: CanvasGrades = enrollment.grades ?? ({} as CanvasGrades);
  return {
    currentScore:
      num(enrollment.computed_current_score) ?? num(g.current_score) ?? num(enrollment.current_score),
    finalScore:
      num(enrollment.computed_final_score) ?? num(g.final_score) ?? num(enrollment.final_score),
    currentGrade: enrollment.computed_current_grade ?? g.current_grade ?? enrollment.current_grade ?? null,
    finalGrade: enrollment.computed_final_grade ?? g.final_grade ?? enrollment.final_grade ?? null,
  };
}

/** Whether an assignment contributes to the course score, per Canvas rules. */
export function countsTowardScore(
  score: number | null,
  pointsPossible: number | null,
  excused: boolean,
  omit: boolean
): boolean {
  return !excused && !omit && pointsPossible !== null && pointsPossible > 0 && score !== null;
}

/**
 * Weighted percentage across assignment groups.
 * Groups with nothing graded yet are dropped and the remaining weights are
 * renormalised, which is what Canvas shows mid-semester.
 */
export function computeWeightedPercent(
  groups: { weight: number; earned: number; possible: number }[]
): number | null {
  const graded = groups.filter((g) => g.possible > 0);
  if (graded.length === 0) return null;
  const totalWeight = graded.reduce((s, g) => s + (g.weight > 0 ? g.weight : 0), 0);
  if (totalWeight > 0) {
    const sum = graded.reduce((s, g) => s + (g.earned / g.possible) * g.weight, 0);
    return (sum / totalWeight) * 100;
  }
  const earned = graded.reduce((s, g) => s + g.earned, 0);
  const possible = graded.reduce((s, g) => s + g.possible, 0);
  return possible > 0 ? (earned / possible) * 100 : null;
}

export function toAssignmentRows(
  course: CanvasCourse,
  courseName: string,
  assignments: CanvasAssignment[],
  groupById: Map<number, { name: string; weight: number }>
): AssignmentRow[] {
  return assignments.map((a) => {
    const sub = a.submission ?? null;
    const score = sub && sub.excused !== true ? num(sub.score) : null;
    const points = num(a.points_possible);
    const group = groupById.get(a.assignment_group_id);
    const percent = score !== null && points !== null && points > 0 ? (score / points) * 100 : null;
    const weight = group?.weight ?? 0;

    return {
      id: a.id,
      courseId: course.id,
      courseName,
      name: a.name,
      dueAt: a.due_at,
      pointsPossible: points,
      groupId: a.assignment_group_id,
      groupName: group?.name ?? '未分组',
      groupWeight: weight,
      score,
      grade: sub?.grade ?? null,
      submittedAt: sub?.submitted_at ?? null,
      gradedAt: sub?.graded_at ?? null,
      workflowState: sub?.workflow_state ?? 'unsubmitted',
      late: sub?.late === true,
      missing: sub?.missing === true,
      excused: sub?.excused === true,
      omitFromFinalGrade: a.omit_from_final_grade === true,
      htmlUrl: a.html_url,
      descriptionExcerpt: makeExcerpt(a.description),
      percent,
      weightedContribution: percent !== null && weight > 0 ? (percent / 100) * weight : null,
    };
  });
}

export function summariseCourse(
  course: CanvasCourse,
  displayName: string,
  nickname: string | undefined,
  rows: AssignmentRow[],
  term: { id: number | null; name: string; startAt: string | null; endAt: string | null }
): CourseSummary {
  const scores = extractScores(pickOwnEnrollment(course));
  const groups = new Map<number, { weight: number; earned: number; possible: number }>();
  for (const r of rows) {
    const g = groups.get(r.groupId) ?? { weight: r.groupWeight, earned: 0, possible: 0 };
    if (countsTowardScore(r.score, r.pointsPossible, r.excused, r.omitFromFinalGrade)) {
      g.earned += r.score as number;
      g.possible += r.pointsPossible as number;
    }
    groups.set(r.groupId, g);
  }
  const weighted = computeWeightedPercent([...groups.values()]);
  const earnedPoints = [...groups.values()].reduce((s, g) => s + g.earned, 0);
  const possiblePoints = [...groups.values()].reduce((s, g) => s + g.possible, 0);
  const now = Date.now();

  return {
    id: course.id,
    name: course.name,
    displayName,
    courseCode: course.course_code,
    nickname,
    termId: term.id,
    termName: term.name,
    termStartAt: term.startAt,
    termEndAt: term.endAt,
    startAt: course.start_at ?? null,
    endAt: course.end_at ?? null,
    imageUrl: course.image_download_url ?? null,
    currentScore: scores.currentScore ?? weighted,
    finalScore: scores.finalScore,
    currentGrade: scores.currentGrade,
    finalGrade: scores.finalGrade,
    earnedPoints: possiblePoints > 0 ? earnedPoints : null,
    possiblePointsGraded: possiblePoints > 0 ? possiblePoints : null,
    assignmentCount: rows.length,
    submittedCount: rows.filter((r) => r.workflowState !== 'unsubmitted').length,
    gradedCount: rows.filter((r) => r.score !== null).length,
    missingCount: rows.filter((r) => r.missing).length,
    lateCount: rows.filter((r) => r.late).length,
    upcomingCount: rows.filter((r) => r.dueAt !== null && Date.parse(r.dueAt) > now).length,
  };
}

/**
 * Work out which semester a course belongs to.
 *
 * `include[]=term` supplies id, name and dates; when it is unavailable (older
 * deployments, or the include being rejected) we still have
 * `enrollment_term_id`, so the course is grouped correctly and merely gets a
 * placeholder label.
 */
export function resolveTerm(
  course: CanvasCourse,
  termInfo: Map<number, CanvasTerm>
): { id: number | null; name: string; startAt: string | null; endAt: string | null } {
  const id = course.term?.id ?? course.enrollment_term_id ?? null;
  if (id === null) {
    return { id: null, name: '未指定学期', startAt: null, endAt: null };
  }
  const info = course.term ?? termInfo.get(id);
  return {
    id,
    name: info?.name?.trim() || `学期 #${id}`,
    startAt: info?.start_at ?? null,
    endAt: info?.end_at ?? null,
  };
}

/** Collect every term object the payload happened to include. */
export function collectTermInfo(courses: CanvasCourse[]): Map<number, CanvasTerm> {
  const map = new Map<number, CanvasTerm>();
  for (const c of courses) {
    if (c.term?.id !== undefined) map.set(c.term.id, c.term);
  }
  return map;
}

/**
 * Group courses into semesters, newest first, and flag the current one.
 *
 * "Current" means the term whose date range contains today; if the dates are
 * missing or no term is in session, the most recently started term wins.
 */
export function buildTermGroups(courses: CourseSummary[]): TermGroup[] {
  const map = new Map<number | null, TermGroup>();

  for (const c of courses) {
    const key = c.termId;
    const existing = map.get(key);
    if (existing) {
      existing.courseCount += 1;
      // Widen the range in case courses inside one term disagree slightly.
      if (c.termStartAt && (!existing.startAt || Date.parse(c.termStartAt) < Date.parse(existing.startAt))) {
        existing.startAt = c.termStartAt;
      }
      if (c.termEndAt && (!existing.endAt || Date.parse(c.termEndAt) > Date.parse(existing.endAt))) {
        existing.endAt = c.termEndAt;
      }
    } else {
      map.set(key, {
        id: key,
        name: c.termName,
        startAt: c.termStartAt,
        endAt: c.termEndAt,
        isCurrent: false,
        courseCount: 1,
      });
    }
  }

  const groups = [...map.values()].sort((a, b) => {
    const ta = a.startAt ? Date.parse(a.startAt) : NaN;
    const tb = b.startAt ? Date.parse(b.startAt) : NaN;
    if (Number.isNaN(ta) && Number.isNaN(tb)) return (b.id ?? -1) - (a.id ?? -1);
    if (Number.isNaN(ta)) return 1; // undated terms sink to the bottom
    if (Number.isNaN(tb)) return -1;
    if (tb !== ta) return tb - ta;
    return (b.id ?? -1) - (a.id ?? -1);
  });

  if (groups.length > 0) {
    const now = Date.now();
    const inSession = groups.find(
      (g) => g.startAt && g.endAt && Date.parse(g.startAt) <= now && now <= Date.parse(g.endAt)
    );
    const started = groups.find((g) => g.startAt && Date.parse(g.startAt) <= now);
    const current = inSession ?? started ?? groups[0];
    for (const g of groups) g.isCurrent = g === current;
  }

  // Canvas sometimes splits one semester into several terms, and derived labels
  // (see `guessTermName`) can collide too. Two identically named chips would be
  // indistinguishable, so append the term id when that happens.
  const nameCounts = new Map<string, number>();
  for (const g of groups) nameCounts.set(g.name, (nameCounts.get(g.name) ?? 0) + 1);
  for (const g of groups) {
    if ((nameCounts.get(g.name) ?? 0) > 1) g.name = `${g.name}（#${g.id ?? '无'}）`;
  }

  return groups;
}

/**
 * Best-effort semester label for caches that predate `include[]=term`.
 *
 * Such a cache still carries the real `enrollment_term_id`, so the grouping is
 * correct, but every term would otherwise read "未指定学期" and be
 * indistinguishable. The course start date is a reliable enough hint: a term
 * beginning in Feb-Jul is the spring one, otherwise the autumn one.
 */
function guessTermName(startAt: string | null | undefined, termId: number | null): string {
  if (startAt) {
    const d = new Date(startAt);
    if (!Number.isNaN(d.getTime())) {
      const month = d.getMonth() + 1;
      const season = month >= 2 && month <= 7 ? '春季' : '秋季';
      return `${d.getFullYear()} 年${season}学期`;
    }
  }
  return termId === null ? '未指定学期' : `学期 #${termId}`;
}

/**
 * Bring a cached snapshot up to the current shape.
 *
 * Caches written by older builds lack fields that newer ones assume - the
 * 0.1.0 cache had no `terms`, and reading it crashed the whole UI at first
 * render. Every cache read therefore goes through here: missing pieces are
 * derived, and an object that cannot be salvaged returns null so the caller
 * falls back to a fresh fetch.
 */
export function normaliseSnapshot(raw: unknown): Snapshot | null {
  if (!raw || typeof raw !== 'object') return null;
  const s = raw as Partial<Snapshot>;
  if (!Array.isArray(s.courses) || !Array.isArray(s.assignments)) return null;

  // Many Canvas courses carry no start date at all, so the earliest assignment
  // due date is used as a stand-in - it is what actually places a course in
  // time, and it keeps term labels distinguishable.
  const earliestByCourse = new Map<number, number>();
  for (const a of s.assignments) {
    if (typeof a?.courseId !== 'number' || !a?.dueAt) continue;
    const t = Date.parse(a.dueAt);
    if (Number.isNaN(t)) continue;
    const prev = earliestByCourse.get(a.courseId);
    if (prev === undefined || t < prev) earliestByCourse.set(a.courseId, t);
  }

  const courses: CourseSummary[] = s.courses.map((c) => {
    const termId = c?.termId ?? null;
    let startAt = c?.termStartAt ?? c?.startAt ?? null;
    if (!startAt && typeof c?.id === 'number') {
      const t = earliestByCourse.get(c.id);
      if (t !== undefined) startAt = new Date(t).toISOString();
    }
    return {
      ...c,
      termId,
      termName: c?.termName ?? guessTermName(startAt, termId),
      termStartAt: startAt,
      termEndAt: c?.termEndAt ?? c?.endAt ?? null,
    };
  });

  const terms =
    Array.isArray(s.terms) && s.terms.length > 0 ? s.terms : buildTermGroups(courses);

  return {
    fetchedAt: typeof s.fetchedAt === 'string' ? s.fetchedAt : new Date(0).toISOString(),
    profile: s.profile ?? ({ id: 0, name: '未知用户' } as CanvasProfile),
    courses,
    terms,
    assignments: s.assignments,
    todo: Array.isArray(s.todo) ? s.todo : [],
    warnings: Array.isArray(s.warnings) ? s.warnings : [],
  };
}

export function buildCourseDetail(snapshot: Snapshot, courseId: number): CourseDetail | null {
  const course = snapshot.courses.find((c) => c.id === courseId);
  if (!course) return null;
  const rows = snapshot.assignments.filter((a) => a.courseId === courseId);

  const byGroup = new Map<number, { name: string; weight: number; earned: number; possible: number }>();
  for (const r of rows) {
    const g = byGroup.get(r.groupId) ?? { name: r.groupName, weight: r.groupWeight, earned: 0, possible: 0 };
    if (countsTowardScore(r.score, r.pointsPossible, r.excused, r.omitFromFinalGrade)) {
      g.earned += r.score as number;
      g.possible += r.pointsPossible as number;
    }
    byGroup.set(r.groupId, g);
  }

  const groups = [...byGroup.entries()]
    .map(([id, g]) => ({
      id,
      name: g.name,
      weight: g.weight,
      earned: g.earned,
      possible: g.possible,
      percent: g.possible > 0 ? (g.earned / g.possible) * 100 : null,
    }))
    .sort((a, b) => b.weight - a.weight || a.name.localeCompare(b.name, 'zh-Hans-CN'));

  return {
    course,
    groups,
    assignments: rows,
    gradingScheme: groups.some((g) => g.weight > 0) ? 'weighted' : 'points',
  };
}
