// Restore the default for a single preference without touching anything else.
// (Automated UI smoke tests clicked the toggle on the real profile.)
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const file = join(process.env.APPDATA ?? '', 'Fudan-eLearning-Dashboard', 'prefs.json');
if (!existsSync(file)) {
  console.log('prefs.json 不存在，无需处理');
  process.exit(0);
}

const prefs = JSON.parse(readFileSync(file, 'utf8'));
console.log('修改前的字段：', Object.keys(prefs).join(', '));
console.log('hideUnsubmitted 原值：', prefs.hideUnsubmitted);

prefs.hideUnsubmitted = false;
writeFileSync(file, JSON.stringify(prefs, null, 2), 'utf8');
console.log('已重置为 false（其他字段原样保留）');
