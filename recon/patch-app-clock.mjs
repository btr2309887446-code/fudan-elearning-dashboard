/**
 * 把界面与演示数据里所有 `DateTime.now()` 换成可冻结的 `appNow()`。
 *
 * golden 截图带相对时间文案（「今天截止（9 小时内）」），不冻结的话
 * 每小时就会失效一次。
 *
 *   node recon/patch-app-clock.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';

const base = 'D:/vit/杂/elearning/flutter_app/lib/';

const targets = [
  { file: `${base}core/demo.dart`, needImport: true },
  { file: `${base}ui/format.dart`, needImport: true },
  { file: `${base}ui/overview_tab.dart`, needImport: true },
  { file: `${base}ui/timeline_tab.dart`, needImport: true },
];

for (const { file, needImport } of targets) {
  let s = readFileSync(file, 'utf8');
  const n = s.split('DateTime.now()').length - 1;
  if (n === 0) {
    console.log(`${file.split('/').pop()}: 没有出现`);
    continue;
  }
  s = s.split('DateTime.now()').join('appNow()');

  if (needImport) {
    // 按相对深度算 import 路径
    const depth = file.includes('/core/') ? "import 'clock.dart';" : "import '../core/clock.dart';";
    if (!s.includes(depth)) {
      // 插到第一个 import 之前
      const i = s.indexOf('import ');
      if (i >= 0) s = s.slice(0, i) + depth + '\n' + s.slice(i);
      else s = depth + '\n\n' + s;
    }
  }

  writeFileSync(file, s, 'utf8');
  console.log(`${file.split('/').pop()}: 替换 ${n} 处`);
}
