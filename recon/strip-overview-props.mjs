/**
 * OverviewTab 不再渲染板块开关栏（挪到设置页了），
 * 把随之失效的 onToggleSection / onMoveSection / onResetOrder 三个 props 删掉，
 * 免得留下没人用的公开参数。
 *
 *   node recon/strip-overview-props.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';

const files = [
  'D:/vit/杂/elearning/flutter_app/lib/ui/overview_tab.dart',
  'D:/vit/杂/elearning/flutter_app/lib/ui/home_shell.dart',
  'D:/vit/杂/elearning/flutter_app/test/ui_test.dart',
];

/** 删掉整行匹配的行（含行首缩进），返回删除条数。 */
function dropLines(s, patterns) {
  const lines = s.split('\n');
  const kept = [];
  let n = 0;
  for (const line of lines) {
    if (patterns.some((re) => re.test(line))) {
      n += 1;
      continue;
    }
    kept.push(line);
  }
  return [kept.join('\n'), n];
}

const patterns = [
  /^\s*required this\.onToggleSection,\s*$/,
  /^\s*required this\.onMoveSection,\s*$/,
  /^\s*required this\.onResetOrder,\s*$/,
  /^\s*onToggleSection,?\s*$/,
  /^\s*onMoveSection,?\s*$/,
  /^\s*onResetOrder,?\s*$/,
  /^\s*final void Function\(String key\) onToggleSection;\s*$/,
  /^\s*final void Function\(String key, int direction\) onMoveSection;\s*$/,
  /^\s*onToggleSection: \(_\) \{\},?\s*$/,
  /^\s*onMoveSection: \(_, __\) \{\},?\s*$/,
  /^\s*onResetOrder: \(\) \{\},?\s*$/,
  /^\s*onToggleSection: \(k\) => state\.toggleDashboardSection\(k\),\s*$/,
  /^\s*onMoveSection: \(k, d\) => state\.moveDashboardSection\(k, d\),\s*$/,
  /^\s*onResetOrder: \(\) => state\.resetDashboardOrder\(\),\s*$/,
];

for (const p of files) {
  let s = readFileSync(p, 'utf8');
  const [out, n] = dropLines(s, patterns);
  writeFileSync(p, out, 'utf8');
  console.log(`${p.split('/').pop()}: 删除 ${n} 行`);
}

// VoidCallback onResetOrder; 是单个字段声明，单独处理
{
  const p = files[0];
  let s = readFileSync(p, 'utf8');
  s = s.replace(/^\s*final VoidCallback onResetOrder;\s*$/m, '');
  writeFileSync(p, s, 'utf8');
}
