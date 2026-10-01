/**
 * 把 App.tsx 里直接调 setSelectedCourse 的地方换成带转场的 openCourse/closeCourse。
 *
 *   node recon/patch-app-nav.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';

const p = 'D:/vit/杂/elearning/src/renderer/src/App.tsx';
let s = readFileSync(p, 'utf8');
let n = 0;

const subs = [
  ['onSelectCourse={(id) => setSelectedCourse(id)}', 'onSelectCourse={openCourse}'],
  ['onBack={() => setSelectedCourse(null)}', 'onBack={closeCourse}'],
  ["onClick={() => setSelectedCourse(null)} title=", 'onClick={closeCourse} title='],
];

for (const [from, to] of subs) {
  const count = s.split(from).length - 1;
  if (count > 0) {
    s = s.split(from).join(to);
    n += count;
    console.log(`  替换 ${count} 处: ${from.slice(0, 50)}`);
  }
}

// Timeline 里连着两行：先切标签再选课程
const tl = ["setTab('overview');", '                setSelectedCourse(id);'].join('\n');
const tlNew = ["setTab('overview');", '                openCourse(id);'].join('\n');
if (s.includes(tl)) {
  s = s.replace(tl, tlNew);
  n += 1;
  console.log('  替换 Timeline 里的跳转');
}

writeFileSync(p, s, 'utf8');
console.log(`共替换 ${n} 处`);
