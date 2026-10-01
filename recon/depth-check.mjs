/**
 * 括号配平检查：逐行算出 {} [] () 的嵌套深度，
 * 用来在重构大段 Dart widget 树时定位结构错位。
 *
 *   node recon/depth-check.mjs <file> [关注行号...]
 */

import { readFileSync } from 'node:fs';

const file = process.argv[2];
const focus = process.argv.slice(3).map(Number);
const lines = readFileSync(file, 'utf8').split('\n');

let depth = 0;
let quote = null;
let inBlock = false;
const depths = [];

for (let i = 0; i < lines.length; i += 1) {
  const line = lines[i];
  let inLine = false;

  for (let j = 0; j < line.length; j += 1) {
    const c = line[j];
    const n = line[j + 1];

    if (inLine) break;
    if (inBlock) {
      if (c === '*' && n === '/') {
        inBlock = false;
        j += 1;
      }
      continue;
    }
    if (quote) {
      if (c === '\\') {
        j += 1;
        continue;
      }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '/' && n === '/') {
      inLine = true;
      break;
    }
    if (c === '/' && n === '*') {
      inBlock = true;
      j += 1;
      continue;
    }
    if (c === "'" || c === '"') {
      quote = c;
      continue;
    }
    if (c === '{' || c === '[' || c === '(') depth += 1;
    else if (c === '}' || c === ']' || c === ')') depth -= 1;
  }

  depths.push({ line: i + 1, depth, text: line.trim().slice(0, 46) });
}

if (focus.length === 0) {
  // 打印所有「深度回到 0」的行——类与方法的分界应当在这些位置
  for (const d of depths) {
    if (d.depth === 0 && d.text) console.log(`${String(d.line).padStart(4)}  depth=0  ${d.text}`);
  }
} else {
  for (const f of focus) {
    const d = depths[f - 1];
    if (d) console.log(`${String(d.line).padStart(4)}  depth=${String(d.depth).padStart(3)}  ${d.text}`);
  }
}

const last = depths[depths.length - 1];
console.log(`--- 末尾 depth=${last.depth}${last.depth === 0 ? ' ✓' : ' ✗ 括号不配平'} ---`);
