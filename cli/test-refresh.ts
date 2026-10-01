/**
 * 刷新范围的纯函数测试。
 *
 * 规则很简单，但错一处就会「历史学期被冻住不再更新」或者
 * 「省了请求却把课程详情搞空」，所以逐条钉住。
 *
 *   node cli/test-refresh.ts
 */

import {
  cachedIds,
  decideRefresh,
  isTermOver,
  planRefresh,
  type RefreshInputs,
} from '../src/core/refresh.ts';

let passed = 0;
let failed = 0;

function check(name: string, ok: boolean, info = ''): void {
  if (ok) {
    passed += 1;
    console.log(`  OK   ${name}${info ? '  — ' + info : ''}`);
  } else {
    failed += 1;
    console.log(` FAIL  ${name}${info ? '  — ' + info : ''}`);
  }
}

function eq<T>(name: string, actual: T, expected: T): void {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  check(name, a === b, a === b ? '' : `得到 ${a}，期望 ${b}`);
}

/** 2026-06-01T00:00:00Z */
const NOW = Date.parse('2026-06-01T00:00:00Z');

function inputs(patch: Partial<RefreshInputs> = {}): RefreshInputs {
  return {
    full: false,
    now: NOW,
    cachedCourseIds: new Set([1, 2, 3]),
    cachedRowCourseIds: new Set([1, 2, 3]),
    ...patch,
  };
}

// [1] isTermOver -------------------------------------------------------------
console.log('\n[1] isTermOver');
{
  check('结束时间在过去 → 已结束', isTermOver('2026-01-15T00:00:00Z', NOW));
  check('结束时间在未来 → 未结束', !isTermOver('2026-09-15T00:00:00Z', NOW));
  check('没有结束时间 → 当作未结束', !isTermOver(null, NOW) && !isTermOver(undefined, NOW));
  check('空串 → 当作未结束', !isTermOver('', NOW));
  check('无法解析 → 当作未结束', !isTermOver('不是日期', NOW));
  // 边界：结束时刻正好等于现在。采用严格小于，也就是当作「还没结束」。
  // 这是更安全的一侧——宁可多请求一次，也别把可能还有末次更新的课冻住。
  check('结束时间正好是现在 → 仍未结束（宁多拉一次）', !isTermOver('2026-06-01T00:00:00Z', NOW));
  check('结束时间比现在早 1 毫秒 → 已结束', isTermOver('2026-05-31T23:59:59.999Z', NOW));
}

// [2] decideRefresh ----------------------------------------------------------
console.log('\n[2] decideRefresh');
{
  const over = '2026-01-15T00:00:00Z';
  const current = '2026-09-15T00:00:00Z';

  eq('已结束 + 有缓存 → 沿用', decideRefresh(1, over, inputs()), 'reuse');
  eq('未结束 → 请求', decideRefresh(1, current, inputs()), 'fetch');
  eq('没有结束时间 → 请求', decideRefresh(1, null, inputs()), 'fetch');
  eq('全量刷新 → 一律请求', decideRefresh(1, over, inputs({ full: true })), 'fetch');

  // 缓存缺一半都不能沿用
  eq(
    '缓存里没有课程汇总 → 请求',
    decideRefresh(9, over, inputs({ cachedCourseIds: new Set([1, 2, 3]) })),
    'fetch'
  );
  eq(
    '缓存里没有作业行 → 请求',
    decideRefresh(1, over, inputs({ cachedRowCourseIds: new Set<number>() })),
    'fetch'
  );
  eq(
    '两样都缺 → 请求',
    decideRefresh(9, over, inputs({ cachedCourseIds: new Set(), cachedRowCourseIds: new Set() })),
    'fetch'
  );
  eq(
    '两样都有 → 沿用',
    decideRefresh(2, over, inputs()),
    'reuse'
  );
}

// [3] planRefresh ------------------------------------------------------------
console.log('\n[3] planRefresh');
{
  const over = '2026-01-15T00:00:00Z';
  const current = '2026-09-15T00:00:00Z';
  const endOf = (c: { id: number; end: string | null }) => c.end;

  const courses = [
    { id: 1, end: over }, // 历史，有缓存
    { id: 2, end: current }, // 当学期
    { id: 3, end: over }, // 历史，有缓存
    { id: 4, end: over }, // 历史，但缓存里没有
  ];

  const p = planRefresh(courses, endOf, inputs());
  eq('要请求的课程', p.fetch.map((c) => c.id), [2, 4]);
  eq('要沿用的课程', p.reuse.map((c) => c.id), [1, 3]);
  check('两组加起来等于全部', p.fetch.length + p.reuse.length === courses.length);

  // 顺序要保持原样，否则界面上课程会跳来跳去
  const p2 = planRefresh(courses, endOf, inputs());
  eq('沿用组保持原顺序', p2.reuse.map((c) => c.id), [1, 3]);

  // 全量
  const pf = planRefresh(courses, endOf, inputs({ full: true }));
  eq('全量刷新时全都要请求', pf.fetch.map((c) => c.id), [1, 2, 3, 4]);
  eq('全量刷新时不沿用任何课', pf.reuse.length, 0);

  // 第一次运行：没有任何缓存
  const pn = planRefresh(courses, endOf, inputs({ cachedCourseIds: new Set(), cachedRowCourseIds: new Set() }));
  eq('没有缓存时全部请求', pn.fetch.length, 4);

  // 空输入不该炸
  const pe = planRefresh([], endOf, inputs());
  eq('空课程列表', [pe.fetch.length, pe.reuse.length], [0, 0]);
}

// [4] cachedIds --------------------------------------------------------------
console.log('\n[4] cachedIds');
{
  const empty = cachedIds(null);
  eq('null 快照给出空集合', [empty.courseIds.size, empty.rowCourseIds.size], [0, 0]);

  const ids = cachedIds({
    courses: [{ id: 1 }, { id: 2 }],
    assignments: [{ courseId: 1 }, { courseId: 1 }, { courseId: 3 }],
  });
  eq('课程 id 去重', [...ids.courseIds].sort(), [1, 2]);
  eq('作业行按课程去重', [...ids.rowCourseIds].sort(), [1, 3]);
  // 关键：课程 3 只有作业行没有汇总，课程 2 只有汇总没有作业行——
  // 两者都不该被当成「缓存齐全」
  check('只有汇总的课程不算齐全', !ids.rowCourseIds.has(2));
  check('只有作业行的课程不算齐全', !ids.courseIds.has(3));
}

console.log(`\n=== 结果：${passed}/${passed + failed} 项通过 ===`);
if (failed > 0) process.exit(1);
