/**
 * 课程卡片上的「缺交 N」改用本机现算的数字。
 *
 * `course.missingCount` 是主进程算好的，它不知道用户在本机标记了哪些
 * 「无需提交」，所以直接用它会让标记失效。
 *
 *   node recon/patch-missing-count.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';

const p = 'D:/vit/杂/elearning/src/renderer/src/components/Dashboard.tsx';
let s = readFileSync(p, 'utf8');

const from = 'c.missingCount';
const to = '(missingByCourse.get(c.id) ?? 0)';
const n = s.split(from).length - 1;
s = s.split(from).join(to);

writeFileSync(p, s, 'utf8');
console.log(`Dashboard: 替换 ${n} 处 c.missingCount`);
