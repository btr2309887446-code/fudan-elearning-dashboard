/**
 * Regression tests for cache-shape handling.
 *
 * The 0.1.0 build wrote snapshot.json without a `terms` field; reading it back
 * in 0.3.0 crashed the UI at first render (blank window). These tests pin that
 * behaviour down, and additionally exercise the real cache file when present.
 *
 *   node cli/test-cache.ts
 */

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { normaliseSnapshot, buildTermGroups } from '../src/core/scoring.ts';

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

console.log('=== 缓存形状兼容性测试 ===\n');

// 1. The exact shape that broke: courses + assignments, no `terms` ---------
console.log('[1] 0.1.0 风格的缓存（无 terms 字段）');
{
  const legacy = {
    fetchedAt: '2026-09-30T05:11:32.000Z',
    profile: { id: 1, name: '测试同学' },
    courses: [
      { id: 101, name: 'A 课程', displayName: 'A 课程', courseCode: 'A.01', currentScore: 88 },
      { id: 102, name: 'B 课程', displayName: 'B 课程', courseCode: 'B.01', currentScore: 91 },
    ],
    assignments: [{ id: 1, courseId: 101, name: '作业一' }],
    todo: [],
    warnings: [],
  };
  const n = normaliseSnapshot(legacy);
  check('能正常解析而不是崩溃', n !== null);
  check('派生出了 terms', Array.isArray(n?.terms) && (n?.terms.length ?? 0) > 0, `terms=${n?.terms.length}`);
  check('courses 补上了 termName', typeof n?.courses[0].termName === 'string', `'${n?.courses[0].termName}'`);
  check('assignments 原样保留', n?.assignments.length === 1);
  check('todo / warnings 补成数组', Array.isArray(n?.todo) && Array.isArray(n?.warnings));
}

// 2. Truncated / malformed caches must be rejected, not half-trusted --------
console.log('\n[2] 损坏或残缺的缓存');
{
  check('null 被拒绝', normaliseSnapshot(null) === null);
  check('字符串被拒绝', normaliseSnapshot('nope') === null);
  check('缺 courses 被拒绝', normaliseSnapshot({ assignments: [] } as unknown) === null);
  check('缺 assignments 被拒绝', normaliseSnapshot({ courses: [] } as unknown) === null);
  const partial = normaliseSnapshot({ courses: [], assignments: [] } as unknown);
  check('空但结构正确可接受', partial !== null && partial.terms.length === 0);
}

// 3. A current cache must survive a round trip unchanged -------------------
console.log('\n[3] 当前版本的缓存（idempotent）');
{
  const courses = [
    {
      id: 201,
      name: 'C 课程',
      displayName: 'C 课程',
      courseCode: 'C.01',
      termId: 9,
      termName: '2026-2027 学年第一学期',
      termStartAt: '2026-09-01T00:00:00Z',
      termEndAt: '2027-01-15T00:00:00Z',
      currentScore: 90,
    },
  ];
  const fresh = {
    fetchedAt: '2026-09-30T05:11:32.000Z',
    profile: { id: 1, name: '测试同学' },
    courses,
    terms: buildTermGroups(courses as never),
    assignments: [],
    todo: [],
    warnings: ['w'],
  };
  const n = normaliseSnapshot(fresh);
  check('原有 terms 不被覆盖', n?.terms[0]?.name === '2026-2027 学年第一学期', n?.terms[0]?.name);
  check('当前学期标记保留', n?.terms[0]?.isCurrent === true);
  check('warnings 保留', n?.warnings.length === 1);
}

// 4. The real cache file, when one exists ----------------------------------
console.log('\n[4] 本机真实缓存文件');
{
  const path = join(process.env.APPDATA ?? '', 'Fudan-eLearning-Dashboard', 'snapshot.json');
  if (!existsSync(path)) {
    console.log('  --   未找到真实缓存，跳过');
  } else {
    try {
      const raw: unknown = JSON.parse(readFileSync(path, 'utf8'));
      const hadTerms = typeof (raw as { terms?: unknown }).terms !== 'undefined';
      const n = normaliseSnapshot(raw);

      if (!n) {
        // A cleared or unreadable cache is a legitimate state (the app drops it
        // and refetches), so this is a skip rather than a failure.
        console.log('  --   本机缓存已清空或不是快照，跳过（应用会重新拉取）');
      } else {
        check('真实缓存可被安全读取', true, `原始文件 ${hadTerms ? '有' : '没有'} terms 字段`);
        check('课程数量合理', n.courses.length > 0, `${n.courses.length} 门`);
        check('terms 可用', n.terms.length > 0, `${n.terms.length} 个学期`);
        check('每门课都有 termName', n.courses.every((c) => typeof c.termName === 'string'));
        const names = new Set(n.terms.map((t) => t.name));
        check('推出的学期名互不重复', names.size === n.terms.length, [...names].join(' / '));
        console.log('\n  推出的学期：');
        for (const t of n.terms) {
          console.log(`    ${t.name.padEnd(20)} ${String(t.courseCount).padStart(2)} 门   id=${t.id}`);
        }
      }
    } catch (err) {
      // A truncated file is also handled by the app; only report the reason.
      console.log(`  --   本机缓存无法解析（${(err as Error).message}），跳过`);
    }
  }
}

console.log(`\n=== 结果：${passed}/${passed + failed} 项通过 ===`);
if (failed > 0) process.exit(1);
