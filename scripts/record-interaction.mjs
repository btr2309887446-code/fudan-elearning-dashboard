// Usage: node scripts/record-interaction.mjs <agent-browser executable> <ffmpeg directory>
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, delimiter } from 'node:path';
const [browser, encoder] = process.argv.slice(2);
if (!browser || !encoder) throw Error('Provide agent-browser executable and ffmpeg directory');
const profile = mkdtempSync(join(tmpdir(), 'elearning-record-'));
writeFileSync(join(profile, 'prefs.json'), JSON.stringify({ theme: 'light' }));
mkdirSync('docs/screenshots', { recursive: true });
const env = { ...process.env, PATH: encoder + delimiter + process.env.PATH };
const session = 'elearning-record-' + Date.now();
const frames = mkdtempSync(join(tmpdir(), 'elearning-frames-'));
const app = spawn(resolve('node_modules/electron/dist/electron.exe'),
  ['scripts/feedback-main.cjs', '--remote-debugging-port=9340', '--force-device-scale-factor=1'], {
    windowsHide: true, stdio: 'ignore', env: { ...env, ELEARNING_DEMO: '1',
      ELEARNING_DEMO_DIR: profile, ELEARNING_RECORD_DIR: frames, ELEARNING_SMOKE_WIDTH: '1200', ELEARNING_SMOKE_HEIGHT: '800' },
  });
function run(...args) {
  const r = spawnSync(browser, ['--session', session, ...args], { env, windowsHide: true, encoding: 'utf8', timeout: 30000 });
  if (r.status !== 0) throw Error(r.stderr || r.stdout || String(r.error));
  return r.stdout;
}
let recording = false;
try {
  await new Promise(resolve => setTimeout(resolve, 1800));
  run('connect', '9340');
  run('snapshot', '-i');
  writeFileSync(join(frames, 'start'), '');
  recording = true;
  run('hover', '.ws-toolbar .primary'); run('wait', '400');
  run('click', '.ws-nav button[title="任务"]');
  run('click', '.ws-toolbar .primary'); run('snapshot', '-i');
  run('fill', 'dialog input[maxlength]', '准备课堂讨论提纲');
  run('fill', 'dialog textarea', '复习重点概念，整理两个讨论问题。');
  run('click', 'dialog button[type="submit"]'); run('wait', '1200');
  const failure = run('get', 'text', 'dialog');
  if (!failure.includes('演示：保存暂时失败')) throw Error('Expected injected save failure');
  run('screenshot', resolve('docs/screenshots/windows-save-failure.png'));
  run('click', 'dialog button[type="submit"]'); run('wait', '1200');
  run('snapshot', '-i', '-s', '.ws-detail');
  run('hover', '.ws-detail .ws-actions button:first-child');
  run('click', '.ws-detail .ws-actions button:first-child'); run('wait', '1000');
  run('click', '.ws-toast button:first-of-type'); run('wait', '800');
  run('click', '.ws-detail-toolbar button');
  run('click', '.ws-filters button'); run('wait', '700');
  run('click', '.ws-filters button'); run('wait', '700');
  writeFileSync(join(frames, 'stop'), ''); recording = false;
  await new Promise(resolve => setTimeout(resolve, 250));
  const files = readdirSync(frames).filter(f => f.endsWith('.jpg')).sort();
  if (files.length < 10) throw Error('Insufficient captured frames');
  const time = name => Number(name.match(/-(\d+)\.jpg$/)[1]);
  const manifest = files.map((f, i) => "file '" + f + "'\nduration " + (i + 1 < files.length ? (time(files[i + 1]) - time(f)) / 1000 : .5)).join('\n') + "\nfile '" + files.at(-1) + "'\n";
  writeFileSync(join(frames, 'frames.txt'), manifest);
  const encoded = spawnSync(join(encoder, 'ffmpeg.exe'), ['-y', '-hide_banner', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', join(frames, 'frames.txt'), '-vf', 'scale=1200:-2', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '22', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', resolve('docs/screenshots/windows-interaction.mp4')], { windowsHide: true, encoding: 'utf8', timeout: 60000 });
  if (encoded.status !== 0) throw Error(encoded.stderr || String(encoded.error));
  console.log('Recorded real pointer interactions, failure/retry, completion/undo and calendar transition.');
} finally {
  if (recording) writeFileSync(join(frames, 'stop'), '');
  try { run('close'); } catch {}
  if (app.exitCode === null) app.kill();
}
