/**
 * 「无需提交」标记的纯函数测试。
 *
 * 这个标记是显示层的：它不该影响任何得分计算，只决定哪些作业
 * 不出现在未交清单和缺交统计里。
 *
 *   node cli/test-ignored.ts
 */

import {
  assignmentKey,
  filterIgnored,
  isIgnored,
  toIgnoredSet,
  toggleIgnored,
} from '../src/core/ignored.ts';

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

// [1] 键的构造 ---------------------------------------------------------------
console.log('\n[1] assignmentKey');
{
  eq('基本形式', assignmentKey(12, 34), '12:34');
  // 只用作业 id 理论上够，但 Canvas 不保证跨课程唯一，带上课程更保险
  check('不同课程同 id 不撞', assignmentKey(1, 7) !== assignmentKey(2, 7));
  check('同课程不同 id 不撞', assignmentKey(1, 7) !== assignmentKey(1, 8));
}

// [2] 判定与集合 -------------------------------------------------------------
console.log('\n[2] isIgnored / toIgnoredSet');
{
  const empty = toIgnoredSet(undefined);
  eq('空集合大小为 0', empty.size, 0);
  check('空集合里什么都不算被标记', !isIgnored(empty, 1, 2));

  const set = toIgnoredSet(['1:2', '3:4']);
  check('命中的算被标记', isIgnored(set, 1, 2));
  check('另一条也命中', isIgnored(set, 3, 4));
  check('没命中的不算', !isIgnored(set, 1, 3));
  check('课程对了 id 不对不算', !isIgnored(set, 1, 9));
  check('id 对了课程不对不算', !isIgnored(set, 9, 2));
}

// [3] 打标记与取消 -----------------------------------------------------------
console.log('\n[3] toggleIgnored');
{
  const a = toggleIgnored([], 1, 2);
  eq('从空列表打标记', a, ['1:2']);

  const b = toggleIgnored(['1:2'], 3, 4);
  eq('追加到后面', b, ['1:2', '3:4']);

  const c = toggleIgnored(['1:2', '3:4'], 1, 2);
  eq('再点一次取消', c, ['3:4']);

  // 取消后剩下的顺序不能乱
  const d = toggleIgnored(['1:1', '2:2', '3:3'], 2, 2);
  eq('取消中间一条后顺序不变', d, ['1:1', '3:3']);

  // 不该改原数组
  const orig = ['1:2'];
  toggleIgnored(orig, 3, 4);
  eq('不改动入参', orig, ['1:2']);

  // 反复点应当回到原点
  let keys: string[] = [];
  for (let i = 0; i < 6; i += 1) keys = toggleIgnored(keys, 5, 6);
  eq('点偶数次等于没点', keys, []);
}

// [4] 批量过滤 ---------------------------------------------------------------
console.log('\n[4] filterIgnored');
{
  const rows = [
    { courseId: 1, id: 10, name: 'a' },
    { courseId: 1, id: 11, name: 'b' },
    { courseId: 2, id: 10, name: 'c' },
  ];

  eq('空集合原样返回', filterIgnored(rows, toIgnoredSet([])).length, 3);

  const one = filterIgnored(rows, toIgnoredSet(['1:10']));
  eq('滤掉一条', one.length, 2);
  eq('留下的是另外两条', one.map((r) => r.name), ['b', 'c']);

  // 课程 2 的 10 号不该被课程 1 的标记误伤
  const cross = filterIgnored(rows, toIgnoredSet(['2:10']));
  eq('跨课程不误伤', cross.map((r) => r.name), ['a', 'b']);

  const all = filterIgnored(rows, toIgnoredSet(['1:10', '1:11', '2:10']));
  eq('全标记就没有了', all.length, 0);

  // 空集合走的是快速路径，应当返回同一个数组引用
  check('空集合走快速路径', filterIgnored(rows, toIgnoredSet([])) === rows);
}

console.log(`\n=== 结果：${passed}/${passed + failed} 项通过 ===`);
if (failed > 0) process.exit(1);
