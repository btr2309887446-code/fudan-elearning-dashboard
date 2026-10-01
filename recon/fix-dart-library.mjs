/**
 * 给带文件级文档注释的 Dart 文件补上 `library;` 指令。
 *
 * Dart 2.19 起，文件开头的 `///` 块要显式跟一个 `library;` 才算库文档，
 * 否则分析器会报 dangling_library_doc_comments。
 *
 * 必须用 Node 而不是 PowerShell 的文本管道：后者按 ANSI 处理，
 * 会把 UTF-8 中文和换行符一起弄坏。
 *
 *   node recon/fix-dart-library.mjs
 */

import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = join(process.cwd(), 'flutter_app');

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    if (entry === '.dart_tool' || entry === 'build' || entry === '.idea') continue;
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) walk(full, out);
    else if (entry.endsWith('.dart')) out.push(full);
  }
  return out;
}

let changed = 0;
for (const file of walk(ROOT)) {
  const text = readFileSync(file, 'utf8');
  const lines = text.split('\n');

  if (!lines[0]?.startsWith('///')) continue;

  // 找到开头连续文档块的最后一行。
  let last = 0;
  while (last + 1 < lines.length && lines[last + 1].startsWith('///')) last++;

  // 已经带了 library; 就跳过。
  const nextMeaningful = lines.slice(last + 1).find((l) => l.trim() !== '');
  if (nextMeaningful?.startsWith('library;')) continue;

  lines.splice(last + 1, 0, '', 'library;');
  writeFileSync(file, lines.join('\n'), 'utf8');
  changed++;
  console.log(`  + ${file.slice(ROOT.length + 1)}`);
}

console.log(`\n共修改 ${changed} 个文件`);
