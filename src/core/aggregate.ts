/**
 * Fetching and assembling the snapshot.
 *
 * The grade arithmetic lives in `scoring.ts` (pure, renderer-safe); this module
 * only deals with talking to Canvas and stitching the results together.
 */

import { CanvasClient } from './canvas.ts';
import { CanvasError, describeCanvasError } from './errors.ts';
import {
  buildTermGroups,
  collectTermInfo,
  resolveTerm,
  summariseCourse,
  toAssignmentRows,
} from './scoring.ts';
import type { AssignmentRow, CanvasCourse, Snapshot } from './types.ts';

// Re-exported so the CLI can keep importing everything from one place.
export {
  buildCourseDetail,
  buildTermGroups,
  collectTermInfo,
  computeWeightedPercent,
  countsTowardScore,
  extractScores,
  pickOwnEnrollment,
  resolveTerm,
  summariseCourse,
  toAssignmentRows,
} from './scoring.ts';

async function mapPool<T, R>(
  items: T[],
  limit: number,
  fn: (item: T, index: number) => Promise<R>
): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let cursor = 0;
  const workers = Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, async () => {
    for (;;) {
      const i = cursor++;
      if (i >= items.length) return;
      out[i] = await fn(items[i], i);
    }
  });
  await Promise.all(workers);
  return out;
}

async function fetchCourseAssignments(
  client: CanvasClient,
  course: CanvasCourse,
  displayName: string,
  warnings: string[]
): Promise<AssignmentRow[]> {
  let groups: { id: number; name: string; group_weight: number }[] = [];
  try {
    groups = await client.getAssignmentGroups(course.id);
  } catch (err) {
    warnings.push(`${displayName}：作业分组获取失败（${describeCanvasError(err)}）`);
  }
  const groupById = new Map(groups.map((g) => [g.id, { name: g.name, weight: g.group_weight ?? 0 }]));

  try {
    const assignments = await client.getAssignments(course.id);
    return toAssignmentRows(course, displayName, assignments, groupById);
  } catch (err) {
    // Losing the session must abort the whole refresh, not silently degrade.
    if (err instanceof CanvasError && err.isAuthFailure) throw err;
    warnings.push(`${displayName}：作业列表获取失败（${describeCanvasError(err)}）`);
    return [];
  }
}

export interface BuildSnapshotOptions {
  enrollmentState?: 'active' | 'all';
  onProgress?: (done: number, total: number, label: string) => void;
}

export async function buildSnapshot(
  client: CanvasClient,
  options: BuildSnapshotOptions = {}
): Promise<Snapshot> {
  const warnings: string[] = [];

  const profile = await client.getProfile();

  let courses = (
    await client.getCourses({
      enrollmentState: options.enrollmentState ?? 'all',
      includeTotalScores: true,
    })
  ).filter((c) => c.workflow_state === 'available');

  // Some Canvas deployments reject the richer includes. Rather than showing an
  // empty dashboard, retry with the bare minimum - scores are recomputed
  // locally from submissions anyway.
  if (courses.length === 0) {
    try {
      const basic = await client.getCourses({ includeTotalScores: false });
      const filtered = basic.filter((c) => c.workflow_state === 'available');
      if (filtered.length > 0) {
        courses = filtered;
        warnings.push('带成绩的课程列表请求被拒绝，已改用基础列表（得分由本地根据作业重新计算）。');
      }
    } catch {
      /* keep the original empty result */
    }
  }

  let nicknames = new Map<number, string>();
  try {
    const list = await client.getCourseNicknames();
    nicknames = new Map(list.map((n) => [n.course_id, n.nickname || n.name]));
  } catch (err) {
    warnings.push(`课程昵称获取失败：${describeCanvasError(err)}`);
  }

  const allRows: AssignmentRow[] = [];
  const termInfo = collectTermInfo(courses);
  let done = 0;

  const details = await mapPool(courses, 4, async (course) => {
    const nickname = nicknames.get(course.id);
    const displayName = nickname || course.name;
    const term = resolveTerm(course, termInfo);
    const rows = await fetchCourseAssignments(client, course, displayName, warnings);
    allRows.push(...rows);
    done += 1;
    options.onProgress?.(done, courses.length, displayName);
    return summariseCourse(course, displayName, nickname, rows, term);
  });

  // Upcoming work -----------------------------------------------------------
  const todo: Snapshot['todo'] = [];
  try {
    const items = await client.getTodo();
    const nameFor = (id: number | undefined) =>
      id === undefined ? '' : (details.find((c) => c.id === id)?.displayName ?? `课程 ${id}`);

    for (const item of items) {
      const a = item.assignment;
      if (a) {
        todo.push({
          title: a.name,
          courseId: item.course_id ?? a.course_id ?? null,
          courseName: nameFor(item.course_id ?? a.course_id),
          dueAt: a.due_at,
          pointsPossible: a.points_possible,
          htmlUrl: a.html_url ?? item.html_url,
          kind: 'assignment',
        });
      } else if (item.quiz) {
        todo.push({
          title: item.quiz.title,
          courseId: item.course_id ?? null,
          courseName: nameFor(item.course_id),
          dueAt: item.quiz.due_at,
          pointsPossible: item.quiz.points_possible,
          htmlUrl: item.quiz.html_url,
          kind: 'quiz',
        });
      }
    }
  } catch (err) {
    warnings.push(`待办事项获取失败：${describeCanvasError(err)}`);
  }

  todo.sort((a, b) => {
    if (!a.dueAt) return 1;
    if (!b.dueAt) return -1;
    return Date.parse(a.dueAt) - Date.parse(b.dueAt);
  });

  details.sort((a, b) => a.displayName.localeCompare(b.displayName, 'zh-Hans-CN'));

  return {
    fetchedAt: new Date().toISOString(),
    profile,
    courses: details,
    terms: buildTermGroups(details),
    assignments: allRows.sort((a, b) => {
      if (!a.dueAt) return 1;
      if (!b.dueAt) return -1;
      return Date.parse(b.dueAt) - Date.parse(a.dueAt);
    }),
    todo,
    warnings,
  };
}
