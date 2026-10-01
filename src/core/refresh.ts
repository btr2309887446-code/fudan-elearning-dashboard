/**
 * 刷新范围：哪些课程必须重新请求，哪些可以沿用上次的数据。
 *
 * 已结束的学期里成绩和作业不会再变，每次刷新都去拉一遍纯属浪费——
 * 一个用了两年的账号里往往只有几门课是当学期，其余全是历史。
 * 每门课要发两个请求（作业分组 + 作业列表），省下的就是这么多。
 */

/** 一门课在这次刷新里该怎么处理。 */
export type RefreshAction = 'fetch' | 'reuse';

export interface RefreshInputs {
  /** 强制全量刷新（忽略缓存）。 */
  full: boolean;
  /** 当前时间戳。做成入参是为了测试能注入。 */
  now: number;
  /** 上次快照里有课程汇总的课程 id。 */
  cachedCourseIds: ReadonlySet<number>;
  /** 上次快照里有作业行的课程 id。 */
  cachedRowCourseIds: ReadonlySet<number>;
}

/**
 * 这个学期是否已经结束。
 *
 * 没有结束时间时返回 false——宁可真去请求一次，也好过把一门还在上的课
 * 当成历史冻住。
 */
export function isTermOver(termEndAt: string | null | undefined, now: number): boolean {
  if (!termEndAt) return false;
  const end = Date.parse(termEndAt);
  return Number.isFinite(end) && end < now;
}

export function decideRefresh(
  courseId: number,
  termEndAt: string | null | undefined,
  inputs: RefreshInputs
): RefreshAction {
  if (inputs.full) return 'fetch';
  // 缓存里缺任何一半都不能沿用：只有课程汇总没有作业行，
  // 课程详情页的表格会空掉；反过来未交清单会漏。
  if (!inputs.cachedCourseIds.has(courseId)) return 'fetch';
  if (!inputs.cachedRowCourseIds.has(courseId)) return 'fetch';
  return isTermOver(termEndAt, inputs.now) ? 'reuse' : 'fetch';
}

/** 把一批课分成「要请求」与「沿用」两组，各自保持原顺序。 */
export function planRefresh<T extends { id: number }>(
  courses: readonly T[],
  termEndOf: (course: T) => string | null | undefined,
  inputs: RefreshInputs
): { fetch: T[]; reuse: T[] } {
  const out: { fetch: T[]; reuse: T[] } = { fetch: [], reuse: [] };
  for (const c of courses) {
    const action = decideRefresh(c.id, termEndOf(c), inputs);
    (action === 'reuse' ? out.reuse : out.fetch).push(c);
  }
  return out;
}

/** 从上次快照里抽出两组 id，喂给 [planRefresh]。 */
export function cachedIds(previous: {
  courses: readonly { id: number }[];
  assignments: readonly { courseId: number }[];
} | null): { courseIds: Set<number>; rowCourseIds: Set<number> } {
  const courseIds = new Set<number>();
  const rowCourseIds = new Set<number>();
  if (!previous) return { courseIds, rowCourseIds };
  for (const c of previous.courses) courseIds.add(c.id);
  for (const r of previous.assignments) rowCourseIds.add(r.courseId);
  return { courseIds, rowCourseIds };
}
