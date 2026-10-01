/**
 * 给 IPC 的 summarySource 类型加上 'none'（正文太短、不需要精简）。
 *
 *   node recon/patch-summary-source.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';

const files = [
  'D:/vit/杂/elearning/src/main/index.ts',
  'D:/vit/杂/elearning/src/preload/index.d.ts',
];

const from = "summarySource: 'llm' | 'fallback'";
const to = "summarySource: 'llm' | 'fallback' | 'none'";

for (const p of files) {
  let s = readFileSync(p, 'utf8');
  const n = s.split(from).length - 1;
  s = s.split(from).join(to);
  writeFileSync(p, s, 'utf8');
  console.log(`${p.split('/').pop()}: ${n} 处`);
}
