import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

// A fresh synthetic account on every run. The first save intentionally fails.
const profile = mkdtempSync(join(tmpdir(), 'elearning-feedback-demo-'));
console.log('交互演示：仅使用虚构数据。首次保存会延迟并模拟失败，重试即可成功。');
const child = spawn(resolve('node_modules/electron/dist/electron.exe'),
  ['scripts/feedback-main.cjs'], {
    windowsHide: true,
    stdio: 'inherit',
    env: { ...process.env, ELEARNING_DEMO: '1', ELEARNING_DEMO_DIR: profile },
  });
child.on('exit', code => process.exit(code ?? 1));
child.on('error', error => { console.error(error); process.exit(1); });
