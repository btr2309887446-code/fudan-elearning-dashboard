import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';

mkdirSync('artifacts/ui', { recursive: true });
const cases = [
  ['overview', 1366, 768, 1, 'light'], ['reading', 1366, 768, 1, 'light'],
  ['reading-dark', 1920, 1080, 1, 'dark'], ['reading-narrow', 800, 600, 1, 'light'],
  ['reading-125', 1366, 768, 1.25, 'light'], ['reading-150', 1366, 768, 1.5, 'dark'],
  ['flow', 1366, 900, 1, 'light'], ['settings', 1366, 900, 1, 'light'], ['changes', 1366, 900, 1, 'light'],
];
for (const [view, width, height, scale, theme] of cases.filter(c => !process.env.COURSE_UI_CASE || c[0] === process.env.COURSE_UI_CASE)) {
  const profile = mkdtempSync(join(tmpdir(), 'elearning-course-ui-'));
  writeFileSync(join(profile, 'prefs.json'), JSON.stringify({ theme }));
  if (view === 'changes') {
    const sourceId = createHash('sha256').update('demo/classroom\ndata').digest('hex').slice(0, 32);
    mkdirSync(join(profile, 'accounts'));
    writeFileSync(join(profile, 'accounts', 'workspace-90210.json'), JSON.stringify({ version: 1, account: 90210, series: [], deadlines: {}, ignored: [], baselines: {}, delivered: {}, changes: [{ id: 'demo-lecture-update', batch: 'demo-batch', at: new Date().toISOString(), courseId: 23110, kind: 'lecture', title: '虚构课堂摘要更新', before: 'a'.repeat(64), after: 'b'.repeat(64), read: false, objectId: JSON.stringify([sourceId, 'demo-23110', 'demo-23110-3']) }] }));
  }
  const packaged = process.env.COURSE_UI_EXE;
  const childEnv = { ...process.env };
  delete childEnv.ELECTRON_RUN_AS_NODE;
  const result = await new Promise((done, reject) => {
    const child = spawn(packaged || resolve('node_modules/electron/dist/electron.exe'),
      [...(packaged ? [] : [view === 'flow' ? 'scripts/feedback-main.cjs' : '.']), `--force-device-scale-factor=${scale}`], {
        windowsHide: true,
        env: { ...childEnv, ELEARNING_DEMO: '1', ELEARNING_DEMO_DIR: profile,
          ELEARNING_SMOKE: `artifacts/ui/windows-course-${view}.png`, ELEARNING_SMOKE_VIEW: view,
          ELEARNING_SMOKE_WIDTH: String(Math.max(800, Math.round(width / scale))),
          ELEARNING_SMOKE_HEIGHT: String(Math.max(600, Math.round(height / scale))),
          ELEARNING_SMOKE_DELAY: '800', ELEARNING_SMOKE_SETTLE: '300',
          ELEARNING_SMOKE_SCRIPT_FILE: resolve('scripts/course-content-ui-driver.js') },
      });
    let output = '';
    child.stdout.on('data', b => output += b); child.stderr.on('data', b => output += b);
    const timeout = setTimeout(() => child.kill(), 60000);
    child.on('error', reject);
    child.on('exit', code => { clearTimeout(timeout); done({ code, output }); });
  });
  if (result.code !== 0 || !result.output.includes('COURSE_UI_PASS') || result.output.includes('driver threw')) {
    console.error(result.output); throw Error(`Course UI failed: ${view}`);
  }
  console.log(`course ${view}: passed (${width}×${height}, ${scale * 100}%, ${theme}${packaged ? ', packaged' : ''})`);
}
