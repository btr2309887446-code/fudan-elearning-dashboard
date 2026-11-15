import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import assert from 'node:assert/strict';
const directory = mkdtempSync(join(tmpdir(), 'elearning-lifecycle-'));
const reportPath = join(directory, 'lifecycle.json');
const executable = process.argv[2] ? resolve(process.argv[2]) : resolve('node_modules/electron/dist/electron.exe');
const code = await new Promise(done => {
  const child = spawn(executable, process.argv[2] ? ['--demo'] : ['.', '--demo'], { windowsHide: true, env: { ...process.env, ELEARNING_DEMO_DIR: directory, ELEARNING_LIFECYCLE_TEST: reportPath }, stdio: 'inherit' });
  const timeout = setTimeout(() => child.kill(), 20000);
  child.on('exit', code => { clearTimeout(timeout); done(code); });
});
assert.equal(code, 0);
const report = JSON.parse(readFileSync(reportPath, 'utf8'));
assert.equal(report.trayClose, true); assert.equal(report.restore, true); assert.equal(report.explicitQuit, true);
console.log('Lifecycle passed:', report);
