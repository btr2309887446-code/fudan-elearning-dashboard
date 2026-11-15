import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
mkdirSync('artifacts/ui', { recursive: true });
for (const [view, width, height, scale, theme] of [['flow',1366,900,1,'light'],['dark',1920,1080,1,'dark'],['narrow',800,600,1,'light'],['125',1366,900,1.25,'light'],['150',1366,900,1.5,'dark'],['reduced',1366,900,1,'light']].filter(c=> !process.env.REVIEW_UI_CASE || c[0] === process.env.REVIEW_UI_CASE)) {
  const profile = mkdtempSync(join(tmpdir(), 'elearning-review-ui-')); writeFileSync(join(profile,'prefs.json'),JSON.stringify({theme}));
  const env = { ...process.env }; delete env.ELECTRON_RUN_AS_NODE;
  const packaged = process.env.REVIEW_UI_EXE;
  const result = await new Promise((done,reject)=>{
    const child = spawn(packaged || resolve('node_modules/electron/dist/electron.exe'), [...(packaged?[]:['scripts/review-test-main.cjs']),`--force-device-scale-factor=${scale}`], {windowsHide:true,env:{...env,ELEARNING_DEMO:'1',ELEARNING_DEMO_DIR:profile,ELEARNING_SMOKE:`artifacts/ui/windows-review-${view}.png`,ELEARNING_SMOKE_VIEW:view,ELEARNING_SMOKE_WIDTH:String(Math.max(800,Math.round(width/scale))),ELEARNING_SMOKE_HEIGHT:String(Math.max(600,Math.round(height/scale))),ELEARNING_SMOKE_SCRIPT_FILE:resolve('scripts/review-ui-driver.js'),ELEARNING_SMOKE_DELAY:'800',ELEARNING_SMOKE_SETTLE:'300'}});
    let output=''; child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>output+=b);const timer=setTimeout(()=>child.kill(),90000);child.on('error',reject);child.on('exit',code=>{clearTimeout(timer);done({code,output});});
  });
  if(result.code !== 0 || !result.output.includes('REVIEW_UI_PASS')) {console.error(result.output);throw Error(`Review UI failed: ${view}`);}
  console.log(`review ${view}: passed`);
}
