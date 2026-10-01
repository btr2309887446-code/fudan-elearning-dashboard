/**
 * Fetching and assembling the snapshot.
 *
 * The grade arithmetic lives in `scoring.ts` (pure, renderer-safe); this module
 * only deals with talking to Canvas and stitching the results together.
 */

import { CanvasClient } from './canvas.ts';
import { CanvasError, describeCanvasError } from './errors.ts';
import { cachedIds, planRefresh } from './refresh.ts';
import {
  buildTermGroups,
  collectTermInfo,
  resolveTerm,
  summariseCourse,
  toAssignmentRows,
} from './scoring.ts';
import type { AssignmentRow, CanvasCourse, CourseSummary, Snapshot } from './types.ts';

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

export { cachedIds, decideRefresh, isTermOver, planRefresh } from './refresh.ts';

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

/**
 * 401/403 到底是「会话失效」还是「这一门课没权限」？
 *
 * **Canvas 对两者都返回 401**，只看状态码分不出来。所以用一个轻量请求探一下：
 * 探针还活着 → 是课程级权限问题；探针也挂了 → 会话真的失效了。
 *
 * 为什么必须区分：不区分的话，一门访问不了的课会让整次刷新中断，
 * 界面报一句「登录状态已失效」——而用户其实是刚登录成功的。
 */
async function sessionIsDead(client: CanvasClient, err: unknown): Promise<boolean> {
  if (!(err instanceof CanvasError) || !err.isAuthFailure) return false;
  try {
    await client.getProfile();
    return false; // 探针成功，会话没问题
  } catch {
    return true; // 探针也 401，会话确实失效了
  }
}

/**
 * 课程级 401 的人话描述。
 *
 * 不能直接用 describeCanvasError——它对 401 会返回
 * 「登录状态已失效，请重新登录。」，在这个语境下是误导。
 */
function authWarning(err: unknown): string {
  const code = err instanceof CanvasError ? err.status : 0;
  return `无权访问（HTTP ${code}），已跳过这门课`;
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
    if (await sessionIsDead(client, err)) throw err;
    const msg =
      err instanceof CanvasError && err.isAuthFailure
        ? `作业分组${authWarning(err)}`
        : `作业分组获取失败（${describeCanvasError(err)}）`;
    warnings.push(`${displayName}：${msg}`);
  }
  const groupById = new Map(groups.map((g) => [g.id, { name: g.name, weight: g.group_weight ?? 0 }]));

  try {
    const assignments = await client.getAssignments(course.id);
    return toAssignmentRows(course, displayName, assignments, groupById);
  } catch (err) {
    if (await sessionIsDead(client, err)) throw err;
    const msg =
      err instanceof CanvasError && err.isAuthFailure
        ? authWarning(err)
        : `作业列表获取失败（${describeCanvasError(err)}）`;
    warnings.push(`${displayName}：${msg}`);
    return [];
  }
}

export interface BuildSnapshotOptions {
  enrollmentState?: 'active' | 'all';
  onProgress?: (done: number, total: number, label: string) => void;
  /**
   * 上一次的快照。已结束学期的课程直接沿用它的汇总与作业行，不再发请求。
   * 传 null 或不传就是全量拉取。
   */
  previous?: Snapshot | null;
  /** 强制全量刷新，忽略 [previous] 里的历史学期数据。 */
  full?: boolean;
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

  // --- 刷新范围 -------------------------------------------------------------
  // 已结束学期的课不会再变，沿用上次的汇总与作业行，省下每门课两个请求。
  const previous = options.previous ?? null;
  const ids = cachedIds(previous);
  const plan = planRefresh(
    courses,
    (c) => resolveTerm(c, termInfo).endAt,
    {
      full: options.full === true,
      now: Date.now(),
      cachedCourseIds: ids.courseIds,
      cachedRowCourseIds: ids.rowCourseIds,
    }
  );

  const reusedSummaries: CourseSummary[] = [];
  if (plan.reuse.length > 0 && previous) {
    const wanted = new Set(plan.reuse.map((c) => c.id));
    for (const c of previous.courses) {
      if (wanted.has(c.id)) reusedSummaries.push(c);
    }
    for (const r of previous.assignments) {
      if (wanted.has(r.courseId)) allRows.push(r);
    }
  }

  let done = 0;
  const fetched = await mapPool(plan.fetch, 4, async (course) => {
    const nickname = nicknames.get(course.id);
    const displayName = nickname || course.name;
    const term = resolveTerm(course, termInfo);
    const rows = await fetchCourseAssignments(client, course, displayName, warnings);
    allRows.push(...rows);
    done += 1;
    options.onProgress?.(done, plan.fetch.length, displayName);
    return summariseCourse(course, displayName, nickname, rows, term);
  });

  const details = [...reusedSummaries, ...fetched];

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
    /** 这次刷新沿用了多少门已结束学期的课（没有为它们发请求）。 */
    reusedCourseCount: reusedSummaries.length,
  };
}
