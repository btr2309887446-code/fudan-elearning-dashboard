/**
 * 扫出「本该插值却漏了 $」的字符串。
 *
 * `'共{assignments.length} 项作业'` 在界面上会原样显示花括号——
 * 编译器不会报错，测试也未必覆盖得到，只能靠扫。
 *
 *   node recon/scan-missing-interp.mjs
 */

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const root = 'D:/vit/杂/elearning/flutter_app/lib';

/** 递归收集 .dart 文件。 */
function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...walk(full));
    else if (name.endsWith('.dart')) out.push(full);
  }
  return out;
}

// 单引号字符串里出现 {identifier} 或 {identifier.something}，但前面没有 $
const suspicious = /(?<!\$)\{[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\}/g;

// 正常的 Dart 语法里会出现的花括号，别误报
const allowed = [
  /^\{\s*\}$/, // 空
  /\{@\w/, // 文档注释宏
];

let hits = 0;
for (const file of walk(root)) {
  const lines = readFileSync(file, 'utf8').split('\n');
  lines.forEach((line, i) => {
    const trimmed = line.trim();
    if (trimmed.startsWith('//') || trimmed.startsWith('///') || trimmed.startsWith('*')) return;
    for (const m of line.matchAll(suspicious)) {
      if (allowed.some((re) => re.test(m[0]))) continue;
      hits += 1;
      const rel = file.replace(root, 'lib').replace(/\\/g, '/');
      console.log(`  ${rel}:${i + 1}  ${m[0]}   ← ${trimmed.slice(0, 76)}`);
    }
  });
}

console.log(hits === 0 ? '✓ 没有发现漏掉 $ 的插值' : `共 ${hits} 处可疑`);
