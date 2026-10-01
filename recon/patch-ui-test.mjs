/**
 * 给 ui_test.dart 里构造 OverviewTab 的地方补上新增的必填 props。
 *
 *   node recon/patch-ui-test.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';

const p = 'D:/vit/杂/elearning/flutter_app/test/ui_test.dart';
let s = readFileSync(p, 'utf8');

const needle = 'onToggleSection: (_) {},';
const add = [
  'onToggleSection: (_) {},',
  'sectionOrder: const [],',
  'onMoveSection: (_, __) {},',
  'onResetOrder: () {},',
].join('\n            ');

let count = 0;
const out = s.replace(new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), () => {
  count += 1;
  return add;
});

writeFileSync(p, out, 'utf8');
console.log(`已给 ${count} 处补上 sectionOrder / onMoveSection / onResetOrder`);
