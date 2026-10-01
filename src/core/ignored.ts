/**
 * 「无需提交」标记。
 *
 * 有些作业本质上不用交——课堂签到、可选的练习、老师明说不用交的——
 * 但 Canvas 仍然把它们算作 unsubmitted，于是永远挂在未交清单里，
 * 把真正要交的东西淹掉。这个标记由用户手动打。
 *
 * 口径与「忽略未提交的作业」一致：**只影响显示，不影响得分**。
 * 未提交且未批改的作业本来就不计入 Canvas 的当前分数，这里也不动它。
 */

/** 偏好里存的是 `courseId:assignmentId`。单用作业 id 理论上也唯一，
 *  但 Canvas 不保证跨课程唯一，带上课程更保险。 */
export function assignmentKey(courseId: number, id: number): string {
  return `${courseId}:${id}`;
}

export function toIgnoredSet(keys: readonly string[] | null | undefined): Set<string> {
  return new Set(keys ?? []);
}

export function isIgnored(
  set: Set<string>,
  courseId: number,
  id: number
): boolean {
  return set.has(assignmentKey(courseId, id));
}

/** 打上或取消标记，返回新的键列表（保持原有顺序）。 */
export function toggleIgnored(
  keys: readonly string[],
  courseId: number,
  id: number
): string[] {
  const key = assignmentKey(courseId, id);
  return keys.includes(key) ? keys.filter((k) => k !== key) : [...keys, key];
}

/** 从一批带 courseId/id 的行里滤掉被标记的。 */
export function filterIgnored<T extends { courseId: number; id: number }>(
  rows: readonly T[],
  set: Set<string>
): T[] {
  if (set.size === 0) return rows as T[];
  return rows.filter((r) => !isIgnored(set, r.courseId, r.id));
}
